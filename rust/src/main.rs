#![allow(dead_code)]

mod types;
mod prefix;
mod model;
mod convert;
mod engine;
mod turtle_oxrdf;
mod turtle_native;
mod ntriples;
mod jsonld;

use anyhow::{Context, Result, bail};
use clap::Parser;
use indexmap::IndexMap;
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::types::*;

#[derive(Parser, Debug)]
#[command(name = "rdf-config")]
#[command(about = "Convert TSV/CSV/DuckDB/SQLite table data to RDF Turtle, N-Triples or JSON-LD format")]
struct Cli {
    /// Path to the configuration folder containing model.yaml, prefix.yaml, convert.yaml
    #[arg(long)]
    config: PathBuf,

    /// Conversion format: `:turtle` (default), `:ntriples` (line-based
    /// N-Triples — one fully-expanded `<s> <p> <o> .` triple per line),
    /// `:jsonld` (a single `@context`/`@graph` document), `:jsonl` (JSON
    /// Lines — one JSON-LD node per line, each referencing an external
    /// `context.jsonld`), or `:context` (just the JSON-LD `{"@context":
    /// {...}}` document).
    #[arg(long, default_value = ":turtle")]
    convert: String,

    /// Number of input rows to process per chunk (controls memory usage)
    #[arg(long, default_value_t = 10)]
    chunk_size: usize,

    /// Turtle serializer backend: "oxrdf" (with IRI validation via oxrdf) or "native" (hand-written)
    #[arg(long, default_value = "oxrdf")]
    serializer: String,

    /// Maximum number of entries in the deduplication set.
    /// Limits memory usage to approximately (N * 8) bytes.
    /// 0 = no deduplication. Default 10,000,000 (~80 MB).
    #[arg(long, default_value_t = 10_000_000)]
    dedup_limit: usize,

    /// Optional: input file path or directory.
    /// File format is detected from the extension:
    /// .tsv/.txt → tab, .csv → comma, .duckdb → DuckDB, .sqlite/.sqlite3 → SQLite.
    /// (.db is ambiguous and requires explicit format in source().)
    /// - File: overrides all source() paths in convert.yaml
    /// - For DuckDB / SQLite input, each rule's source() third argument supplies
    ///   the table name (rules without it are an error).
    /// - Directory: resolves source() paths relative to this directory
    /// - Omitted: uses source() entries from convert.yaml as-is
    input: Option<PathBuf>,
}

/// Output format selected by `--convert`. Carried through the streaming
/// writers so each chunk is serialized the right way.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ConvertMode {
    /// Turtle (`:turtle`).
    Turtle,
    /// N-Triples (`:ntriples`): one canonical `<s> <p> <o> .` line per
    /// triple, with every IRI written out in full and no prefix prelude.
    NTriples,
    /// JSON-LD as one `{"@context": {...}, "@graph": [...]}` document (`:jsonld`).
    JsonLd,
    /// JSON-LD as JSON Lines: one node per line, each with
    /// `"@context": "context.jsonld"` (`:jsonl`).
    JsonLines,
    /// Only the JSON-LD `{"@context": {...}}` document (`:context`).
    /// Handled specially in `main`: it never reads input rows.
    Context,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let out_mode = match cli.convert.as_str() {
        ":turtle" => ConvertMode::Turtle,
        ":ntriples" => ConvertMode::NTriples,
        ":jsonld" => ConvertMode::JsonLd,
        ":jsonl" => ConvertMode::JsonLines,
        ":context" => ConvertMode::Context,
        _ => bail!(
            "--convert must be \":turtle\", \":ntriples\", \":jsonld\", \":jsonl\", or \":context\""
        ),
    };
    if cli.serializer != "oxrdf" && cli.serializer != "native" {
        bail!("--serializer must be \"oxrdf\" or \"native\"");
    }

    // Load configuration files
    let config_dir = &cli.config;
    let prefixes = prefix::parse_prefix_yaml(&config_dir.join("prefix.yaml"))
        .with_context(|| "Failed to parse prefix.yaml")?;
    let model_def = model::parse_model_yaml(&config_dir.join("model.yaml"), &prefixes)
        .with_context(|| "Failed to parse model.yaml")?;

    // Validate model.yaml itself for internal consistency (no duplicate
    // subject/object names) before doing anything else with it.
    validate_model(&model_def)?;

    // Reject any name that is used both as a model.yaml object name and as a
    // prefix.yaml prefix: the two namespaces must stay disjoint.
    validate_object_names_vs_prefixes(&model_def, &prefixes)?;

    let convert_config = convert::parse_convert_yaml(&config_dir.join("convert.yaml"))
        .with_context(|| "Failed to parse convert.yaml")?;

    // Validate that every subject/object name used in convert.yaml is
    // actually defined in model.yaml (fail fast with all errors, before
    // we open input files or do any work).
    validate_convert_against_model(&convert_config, &model_def)?;

    // ── `:context` — emit only the JSON-LD context document ──
    // This needs nothing but model.yaml + prefix.yaml; it never reads input
    // rows, so it returns here, before any data source is resolved or opened.
    if out_mode == ConvertMode::Context {
        let name_maps = jsonld::NameMaps::from_model(&model_def, &prefixes);
        let stdout = io::stdout();
        let mut buf_writer = BufWriter::new(stdout.lock());
        jsonld::write_context_document(&mut buf_writer, &prefixes, &name_maps)?;
        buf_writer.flush()?;
        return Ok(());
    }

    let chunk_size = cli.chunk_size.max(1);
    let dedup_limit = cli.dedup_limit;
    let use_oxrdf = cli.serializer == "oxrdf";

    // ── Group subject rules by source file ──
    let source_groups = group_rules_by_source(&convert_config, cli.input.as_deref())?;

    // ── Set up shared output state ──
    let stdout = io::stdout();
    let mut buf_writer = BufWriter::new(stdout.lock());
    // Precompute model-name → IRI mappings once for JSON-LD output. Kept
    // outside the `match` so the `&NameMaps` reference borrowed below
    // outlives the whole processing loop.
    let name_maps = jsonld::NameMaps::from_model(&model_def, &prefixes);
    match out_mode {
        // The `@graph` document needs an opening `{ "@context": ... }` prelude.
        ConvertMode::JsonLd => jsonld::write_prelude(&mut buf_writer, &prefixes, &name_maps)?,
        // JSON Lines has no document wrapper — nodes start straight away.
        ConvertMode::JsonLines => {}
        // Turtle starts with its `@prefix` declarations.
        ConvertMode::Turtle => turtle_native::write_prefixes(&mut buf_writer, &prefixes)?,
        // N-Triples has no prefix mechanism and no document wrapper — every
        // triple line stands alone, so nothing precedes the first one.
        ConvertMode::NTriples => {}
        // `:context` returned earlier and never reaches this point.
        ConvertMode::Context => unreachable!(),
    }

    let mut first_subject = true;
    let mut seen: HashSet<u64> = HashSet::new();

    // ── Process each source with its associated rules ──
    for (source_spec, rule_indices) in &source_groups {
        // Build a sub-ConvertConfig containing only the rules for this source
        let sub_config = ConvertConfig {
            subject_rules: rule_indices.iter()
                .map(|&i| convert_config.subject_rules[i].clone())
                .collect(),
        };

        process_source(
            source_spec, &sub_config, &model_def, &prefixes, &name_maps,
            chunk_size, dedup_limit, use_oxrdf, out_mode,
            &mut buf_writer, &mut first_subject, &mut seen,
        ).with_context(|| format!("Failed processing source: {}", source_spec.display()))?;
    }

    // Only the `@graph` document needs a closing `] }`. JSON Lines and
    // Turtle are complete as soon as their last node/triple is written.
    if out_mode == ConvertMode::JsonLd {
        // `first_subject` is still true iff zero subjects were emitted.
        jsonld::write_postlude(&mut buf_writer, !first_subject)?;
    }

    buf_writer.flush()?;
    Ok(())
}

// ─── model.yaml internal consistency check ────────────────────────

/// Verify that names in model.yaml are unique:
/// - Subject names are unique across the whole model.
/// - Object names are unique across the whole model (collapsing direct
///   predicate objects and blank-node-group objects, since convert.yaml
///   references them by bare name without naming the surrounding subject
///   or predicate).
///
/// For object duplicates, the error message lists every subject the name
/// appears under, including a (×N) suffix when the same subject has
/// multiple definitions of the name.
fn validate_model(model: &Model) -> Result<()> {
    let mut errors: Vec<String> = Vec::new();

    // ── subject-name uniqueness across the whole model ──
    {
        let mut seen: HashSet<&str> = HashSet::new();
        let mut reported: HashSet<&str> = HashSet::new();
        for subject in &model.subjects {
            let name = subject.name.as_str();
            if !seen.insert(name) && reported.insert(name) {
                errors.push(format!(
                    "Subject '{}' is defined more than once in model.yaml",
                    name
                ));
            }
        }
    }

    // ── object-name uniqueness across the entire model ──
    // For every object name, record each subject under which it appears
    // (with multiplicity). IndexMap preserves first-appearance order so
    // error output is stable.
    //
    // Objects with an empty name are skipped. An empty name means the object
    // is anonymous — it arises from blank-node-internal structure (e.g. an
    // `a:` type marker or a bare value inside a `[]` blank node) rather than
    // from a named `objectName: value` entry. The uniqueness rule exists so
    // that convert.yaml object references resolve unambiguously; an anonymous
    // object cannot be named in convert.yaml at all, so the rule does not
    // apply to it. Without this skip, two or more anonymous objects under the
    // same subject would be misreported as a duplicate definition of `''`.
    // object-name uniqueness, anonymous objects skipped. `leaf_objects()`
    // recurses through nested blank nodes, so an object name defined deep
    // inside a `[]` chain is checked the same as a top-level one.
    let mut occurrences: IndexMap<&str, Vec<&str>> = IndexMap::new();
    for subject in &model.subjects {
        let subject_name = subject.name.as_str();
        for (obj, _pred) in subject.leaf_objects() {
            if obj.name.is_empty() {
                continue;
            }
            occurrences.entry(obj.name.as_str()).or_default().push(subject_name);
        }
    }

    for (name, subjects) in &occurrences {
        if subjects.len() <= 1 {
            continue;
        }
        // Collapse repeated subjects into "subject 'X' (×N)" form.
        let mut by_subject: IndexMap<&str, usize> = IndexMap::new();
        for s in subjects {
            *by_subject.entry(*s).or_insert(0) += 1;
        }
        let location_list = by_subject.iter()
            .map(|(s, &count)| {
                if count > 1 {
                    format!("subject '{}' (×{})", s, count)
                } else {
                    format!("subject '{}'", s)
                }
            })
            .collect::<Vec<_>>()
            .join(", ");
        errors.push(format!(
            "Object '{}' is defined more than once in model.yaml: {}",
            name, location_list
        ));
    }

    if !errors.is_empty() {
        bail!(
            "model.yaml has duplicate definitions:\n  - {}",
            errors.join("\n  - ")
        );
    }
    Ok(())
}

// ─── model.yaml ↔ prefix.yaml namespace-collision check ───────────

/// Verify that no name is used both as a model.yaml object name and as a
/// prefix.yaml prefix.
///
/// The two are distinct namespaces — object names label values referenced
/// from convert.yaml, prefixes expand CURIEs — but they are written in the
/// same identifier style, and a name that lives in both becomes ambiguous
/// (most visibly in the JSON-LD `@context`, where each prefix and each
/// object name contributes a term, and a clash would silently shadow one
/// with the other). We reject the configuration up front instead.
///
/// Object names are collected the same way as in [`validate_model`]:
/// `leaf_objects()` descends through nested blank nodes, and anonymous
/// objects (empty name) are skipped because they can never be referenced by
/// name and so cannot collide with a prefix.
///
/// The error lists every offending name together with the subject(s) it
/// appears under in model.yaml and the IRI it maps to in prefix.yaml, so the
/// duplicated value is unambiguous.
fn validate_object_names_vs_prefixes(model: &Model, prefixes: &PrefixMap) -> Result<()> {
    // Object name -> subjects it appears under (first-appearance order).
    let mut occurrences: IndexMap<&str, Vec<&str>> = IndexMap::new();
    for subject in &model.subjects {
        let subject_name = subject.name.as_str();
        for (obj, _pred) in subject.leaf_objects() {
            if obj.name.is_empty() {
                continue;
            }
            occurrences.entry(obj.name.as_str()).or_default().push(subject_name);
        }
    }

    let mut errors: Vec<String> = Vec::new();
    for (name, subjects) in &occurrences {
        let Some(prefix_iri) = prefixes.get(*name) else {
            continue;
        };
        // De-duplicate subjects while preserving first-appearance order.
        let mut seen: HashSet<&str> = HashSet::new();
        let subject_list = subjects.iter()
            .copied()
            .filter(|s| seen.insert(*s))
            .map(|s| format!("'{}'", s))
            .collect::<Vec<_>>()
            .join(", ");
        errors.push(format!(
            "'{}' is both an object name in model.yaml (under subject {}) \
             and a prefix in prefix.yaml (mapped to <{}>)",
            name, subject_list, prefix_iri
        ));
    }

    if !errors.is_empty() {
        bail!(
            "model.yaml object names collide with prefix.yaml prefixes:\n  - {}",
            errors.join("\n  - ")
        );
    }
    Ok(())
}

// ─── convert.yaml ↔ model.yaml consistency check ──────────────────

/// Verify that every subject name and every object name referenced in
/// convert.yaml is defined in model.yaml. Collects all errors and reports
/// them at once so the user can fix everything in a single pass.
///
/// Object names live under predicates in model.yaml, and may be nested
/// inside blank-node groups; both locations are searched.
fn validate_convert_against_model(
    convert: &ConvertConfig,
    model: &Model,
) -> Result<()> {
    // Index model subjects by name for O(1) lookup.
    let model_subjects: HashMap<&str, &SubjectDef> = model.subjects.iter()
        .map(|s| (s.name.as_str(), s))
        .collect();

    let mut errors: Vec<String> = Vec::new();

    for rule in &convert.subject_rules {
        let Some(subject_def) = model_subjects.get(rule.name.as_str()) else {
            errors.push(format!(
                "Subject '{}' used in convert.yaml is not defined in model.yaml",
                rule.name
            ));
            // Skip object checks for this rule: we can't compare against a
            // model definition that doesn't exist.
            continue;
        };

        // Collect all object names declared anywhere under this subject,
        // descending into nested blank nodes to any depth.
        let mut model_object_names: HashSet<&str> = HashSet::new();
        for (obj, _pred) in subject_def.leaf_objects() {
            model_object_names.insert(obj.name.as_str());
        }

        for obj_rule in &rule.object_rules {
            if !model_object_names.contains(obj_rule.name.as_str()) {
                errors.push(format!(
                    "Object '{}' under subject '{}' used in convert.yaml \
                     is not defined in model.yaml",
                    obj_rule.name, rule.name
                ));
            }
        }
    }

    if !errors.is_empty() {
        bail!(
            "convert.yaml references names that are not defined in model.yaml:\n  - {}",
            errors.join("\n  - ")
        );
    }
    Ok(())
}

// ─── source specification ─────────────────────────────────────────

/// A resolved data source. Each variant maps to a different streaming reader.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
enum SourceSpec {
    /// CSV/TSV file. The delimiter is part of the identity so that the same
    /// `.tsv` and `.csv` file path won't collapse into the same group.
    Tabular { path: PathBuf, delimiter: u8 },
    /// DuckDB database file plus a single table within it.
    DuckDb { path: PathBuf, table: String },
    /// SQLite database file plus a single table within it.
    Sqlite { path: PathBuf, table: String },
}

impl SourceSpec {
    fn display(&self) -> String {
        match self {
            SourceSpec::Tabular { path, .. } => path.display().to_string(),
            SourceSpec::DuckDb { path, table } => format!("{}#{}", path.display(), table),
            SourceSpec::Sqlite { path, table } => format!("{}#{}", path.display(), table),
        }
    }
}

// ─── source resolution ────────────────────────────────────────────

/// Group subject rule indices by their resolved data source.
/// Preserves first-appearance order.
///
/// Resolution logic:
/// - `input` is a file (CLI override):
///     * `.tsv`/`.csv` → ALL rules share that file (source() in convert.yaml is ignored
///       for path/format purposes; source_table is also ignored).
///     * `.duckdb`     → the file is shared, but each rule's source_table (3rd arg of
///       source()) supplies the table name. Rules without source_table → error.
/// - `input` is a directory → each rule's source() spec is used, with relative
///   paths resolved against this directory.
/// - `input` is None → each rule's source() spec is used as-is. Rules without
///   source() inherit the first source() found, or error.
fn group_rules_by_source(
    config: &ConvertConfig,
    input: Option<&Path>,
) -> Result<IndexMap<SourceSpec, Vec<usize>>> {
    if let Some(path) = input {
        if !path.exists() {
            bail!("Input file or directory does not exist: {}", path.display());
        }
        if path.is_file() {
            return resolve_cli_input_file(config, path);
        }
        if !path.is_dir() {
            bail!(
                "Input path is neither a regular file nor a directory: {}",
                path.display()
            );
        }
        // Directory: resolve source() entries with this as base
        return resolve_from_rules(config, Some(path));
    }
    resolve_from_rules(config, None)
}

/// CLI input is a regular file → take it as the source for every rule.
/// Format is detected from the extension. For database formats (DuckDB, SQLite),
/// table names come from each rule's `source_table` (3rd arg of `source()`).
fn resolve_cli_input_file(
    config: &ConvertConfig,
    path: &Path,
) -> Result<IndexMap<SourceSpec, Vec<usize>>> {
    let format = format_from_extension(path)
        .with_context(|| format!("Cannot determine format from extension: {}", path.display()))?;

    let mut groups: IndexMap<SourceSpec, Vec<usize>> = IndexMap::new();

    match format {
        SourceFormat::Tsv | SourceFormat::Csv => {
            let spec = SourceSpec::Tabular {
                path: path.to_path_buf(),
                delimiter: delimiter_for(format),
            };
            let indices: Vec<usize> = (0..config.subject_rules.len()).collect();
            groups.insert(spec, indices);
        }
        SourceFormat::DuckDb | SourceFormat::Sqlite => {
            let format_name = match format {
                SourceFormat::DuckDb => "DuckDB",
                SourceFormat::Sqlite => "SQLite",
                _ => unreachable!(),
            };
            let format_key = match format {
                SourceFormat::DuckDb => "duckdb",
                SourceFormat::Sqlite => "sqlite",
                _ => unreachable!(),
            };
            for (i, rule) in config.subject_rules.iter().enumerate() {
                let table = rule.source_table.as_ref().ok_or_else(|| {
                    anyhow::anyhow!(
                        "Rule '{}' has no table name. When the input file is a {} \
                         database, each rule must specify the table via the 3rd argument \
                         of source(), e.g. source(\"...\", :{}, \"<table>\")",
                        rule.name, format_name, format_key
                    )
                })?;
                let spec = match format {
                    SourceFormat::DuckDb => SourceSpec::DuckDb {
                        path: path.to_path_buf(),
                        table: table.clone(),
                    },
                    SourceFormat::Sqlite => SourceSpec::Sqlite {
                        path: path.to_path_buf(),
                        table: table.clone(),
                    },
                    _ => unreachable!(),
                };
                groups.entry(spec).or_default().push(i);
            }
        }
    }

    Ok(groups)
}

/// No CLI override (or CLI is a directory) → use each rule's source() spec.
fn resolve_from_rules(
    config: &ConvertConfig,
    base_dir: Option<&Path>,
) -> Result<IndexMap<SourceSpec, Vec<usize>>> {
    // Find the first complete source() as fallback for rules without one.
    // We carry path + format + table together so the inheritance is consistent.
    let default_source: Option<(String, Option<SourceFormat>, Option<String>)> =
        config.subject_rules.iter()
            .find(|r| r.source_path.is_some())
            .map(|r| (
                r.source_path.clone().unwrap(),
                r.source_format,
                r.source_table.clone(),
            ));

    let mut groups: IndexMap<SourceSpec, Vec<usize>> = IndexMap::new();

    for (i, rule) in config.subject_rules.iter().enumerate() {
        let (path_str, format, table) = if rule.source_path.is_some() {
            (
                rule.source_path.clone().unwrap(),
                rule.source_format,
                rule.source_table.clone(),
            )
        } else if let Some(ref ds) = default_source {
            ds.clone()
        } else {
            bail!("Rule '{}' has no source() and no input file specified", rule.name);
        };

        let path = resolve_source_path(&path_str, base_dir);
        let spec = build_source_spec(&path, format, table.as_deref(), &rule.name)?;
        groups.entry(spec).or_default().push(i);
    }

    Ok(groups)
}

/// Resolve a source path, optionally relative to a base directory.
fn resolve_source_path(source: &str, base_dir: Option<&Path>) -> PathBuf {
    let p = PathBuf::from(source);
    if p.is_relative() {
        if let Some(base) = base_dir {
            return base.join(&p);
        }
    }
    p
}

/// Build a SourceSpec from path + optional format + optional table.
/// Format is resolved either from the explicit keyword (preferred) or from
/// the file extension. DuckDB requires a table name; CSV/TSV must not have one.
fn build_source_spec(
    path: &Path,
    format: Option<SourceFormat>,
    table: Option<&str>,
    rule_name: &str,
) -> Result<SourceSpec> {
    let fmt = match format {
        Some(f) => f,
        None => format_from_extension(path).with_context(|| {
            format!(
                "Rule '{}': cannot determine format for {} (no explicit format \
                 in source() and unrecognized extension)",
                rule_name,
                path.display()
            )
        })?,
    };

    match fmt {
        SourceFormat::Tsv | SourceFormat::Csv => {
            // table should already have been rejected by parse_source_call,
            // but keep a defense-in-depth check.
            if table.is_some() {
                bail!(
                    "Rule '{}': table name (3rd arg of source()) is only valid \
                     with database formats (:duckdb, :sqlite)",
                    rule_name
                );
            }
            Ok(SourceSpec::Tabular {
                path: path.to_path_buf(),
                delimiter: delimiter_for(fmt),
            })
        }
        SourceFormat::DuckDb => {
            let t = table.ok_or_else(|| {
                anyhow::anyhow!(
                    "Rule '{}': :duckdb source requires a table name as the 3rd \
                     argument of source(), e.g. source(\"db.duckdb\", :duckdb, \"<table>\")",
                    rule_name
                )
            })?;
            Ok(SourceSpec::DuckDb {
                path: path.to_path_buf(),
                table: t.to_string(),
            })
        }
        SourceFormat::Sqlite => {
            let t = table.ok_or_else(|| {
                anyhow::anyhow!(
                    "Rule '{}': :sqlite source requires a table name as the 3rd \
                     argument of source(), e.g. source(\"db.sqlite\", :sqlite, \"<table>\")",
                    rule_name
                )
            })?;
            Ok(SourceSpec::Sqlite {
                path: path.to_path_buf(),
                table: t.to_string(),
            })
        }
    }
}

/// Determine `SourceFormat` from a file extension.
/// - `.tsv`, `.txt` → Tsv
/// - `.csv` → Csv
/// - `.duckdb` → DuckDb
/// - `.sqlite`, `.sqlite3` → Sqlite
/// - `.db` → ambiguous (both DuckDB and SQLite use it); explicit format required
///
/// `.txt` files are assumed to be tab-separated, the most common convention
/// for plain-text tabular dumps.
///
/// Case-insensitive.
fn format_from_extension(path: &Path) -> Result<SourceFormat> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_ascii_lowercase());

    match ext.as_deref() {
        Some("tsv") | Some("txt") => Ok(SourceFormat::Tsv),
        Some("csv") => Ok(SourceFormat::Csv),
        Some("duckdb") => Ok(SourceFormat::DuckDb),
        Some("sqlite") | Some("sqlite3") => Ok(SourceFormat::Sqlite),
        Some("db") => bail!(
            "The .db extension is ambiguous (used by both DuckDB and SQLite); \
             specify the format explicitly via the 2nd argument of source(), \
             e.g. source(\"{}\", :sqlite, \"<table>\"): {}",
            path.display(),
            path.display()
        ),
        Some(other) => bail!(
            "Unsupported input file extension: '.{}' \
             (expected .tsv, .txt, .csv, .duckdb, .sqlite, or .sqlite3): {}",
            other,
            path.display()
        ),
        None => bail!(
            "Input file has no extension; cannot determine format: {}",
            path.display()
        ),
    }
}

fn delimiter_for(fmt: SourceFormat) -> u8 {
    match fmt {
        SourceFormat::Tsv => b'\t',
        SourceFormat::Csv => b',',
        // Database formats are not delimited; this is unreachable from
        // call sites, but we return tab to keep the function total.
        SourceFormat::DuckDb | SourceFormat::Sqlite => b'\t',
    }
}

// ─── per-source dispatch ──────────────────────────────────────────

fn process_source<W: Write>(
    spec: &SourceSpec,
    sub_config: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    name_maps: &jsonld::NameMaps,
    chunk_size: usize,
    dedup_limit: usize,
    use_oxrdf: bool,
    out_mode: ConvertMode,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
) -> Result<()> {
    match spec {
        SourceSpec::Tabular { path, delimiter } => process_tabular_file(
            path, *delimiter, sub_config, model, prefixes, name_maps,
            chunk_size, dedup_limit, use_oxrdf, out_mode,
            writer, first_subject, seen,
        ),
        SourceSpec::DuckDb { path, table } => {
            #[cfg(feature = "duckdb")]
            {
                process_duckdb_table(
                    path, table, sub_config, model, prefixes, name_maps,
                    chunk_size, dedup_limit, use_oxrdf, out_mode,
                    writer, first_subject, seen,
                )
            }
            #[cfg(not(feature = "duckdb"))]
            {
                bail!(
                    "DuckDB input ({}#{}) requires a build with DuckDB support. \
                     Rebuild with `cargo build --release --features duckdb` \
                     (or `--features all-databases` for both DuckDB and SQLite).",
                    path.display(), table
                )
            }
        }
        SourceSpec::Sqlite { path, table } => {
            #[cfg(feature = "sqlite")]
            {
                process_sqlite_table(
                    path, table, sub_config, model, prefixes, name_maps,
                    chunk_size, dedup_limit, use_oxrdf, out_mode,
                    writer, first_subject, seen,
                )
            }
            #[cfg(not(feature = "sqlite"))]
            {
                bail!(
                    "SQLite input ({}#{}) requires a build with SQLite support. \
                     Rebuild with `cargo build --release --features sqlite` \
                     (or `--features all-databases` for both DuckDB and SQLite).",
                    path.display(), table
                )
            }
        }
    }
}

// ─── CSV/TSV streaming reader ─────────────────────────────────────

fn process_tabular_file<W: Write>(
    source_path: &Path,
    delimiter: u8,
    sub_config: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    name_maps: &jsonld::NameMaps,
    chunk_size: usize,
    dedup_limit: usize,
    use_oxrdf: bool,
    out_mode: ConvertMode,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
) -> Result<()> {
    let mut csv_reader = csv::ReaderBuilder::new()
        .delimiter(delimiter)
        .has_headers(true)
        .flexible(true)
        .from_path(source_path)
        .with_context(|| format!("Failed to open input file: {}", source_path.display()))?;

    let headers: Vec<String> = csv_reader.headers()
        .with_context(|| "Failed to read input file headers")?
        .iter()
        .map(|h| h.to_string())
        .collect();

    let mut chunk: Vec<HashMap<String, String>> = Vec::with_capacity(chunk_size);
    let source_str = source_path.display().to_string();
    // Header is row 1; first data row is row 2
    let mut next_row_num = 2usize;

    for result in csv_reader.records() {
        let record = result.with_context(|| "Failed to read input record")?;
        chunk.push(record_to_row(&record, &headers));

        if chunk.len() >= chunk_size {
            let chunk_start = next_row_num;
            next_row_num += chunk.len();
            flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                        use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                        &source_str, chunk_start)?;
            chunk.clear();
        }
    }
    if !chunk.is_empty() {
        let chunk_start = next_row_num;
        flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                    use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                    &source_str, chunk_start)?;
    }

    Ok(())
}

// ─── DuckDB streaming reader ──────────────────────────────────────

/// Stream rows from a DuckDB table, converting every column to VARCHAR in SQL
/// so the engine receives uniform string values regardless of the column type.
/// NULL values become empty strings (matching the convention of empty TSV cells).
#[cfg(feature = "duckdb")]
fn process_duckdb_table<W: Write>(
    db_path: &Path,
    table: &str,
    sub_config: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    name_maps: &jsonld::NameMaps,
    chunk_size: usize,
    dedup_limit: usize,
    use_oxrdf: bool,
    out_mode: ConvertMode,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
) -> Result<()> {
    let conn = duckdb::Connection::open(db_path)
        .with_context(|| format!("Failed to open DuckDB file: {}", db_path.display()))?;

    let table_sql = quote_qualified_ident(table);

    // Step 1: get column names via DESCRIBE so we can build a SELECT that
    // casts every column to VARCHAR.
    let column_names: Vec<String> = {
        let mut describe = conn
            .prepare(&format!("DESCRIBE {}", table_sql))
            .with_context(|| format!("Failed to describe DuckDB table '{}'", table))?;
        let iter = describe
            .query_map([], |row| row.get::<_, String>(0))
            .with_context(|| format!("Failed to query columns of DuckDB table '{}'", table))?;
        let mut names = Vec::new();
        for r in iter {
            names.push(r.with_context(|| {
                format!("Failed to read column name from DuckDB table '{}'", table)
            })?);
        }
        names
    };

    if column_names.is_empty() {
        bail!("DuckDB table '{}' has no columns", table);
    }

    // Step 2: build SELECT with explicit VARCHAR casts. Aliasing back to the
    // original column name preserves the header for downstream code.
    let select_cols = column_names
        .iter()
        .map(|c| format!("CAST({col} AS VARCHAR) AS {col}", col = quote_ident(c)))
        .collect::<Vec<_>>()
        .join(", ");
    let select_sql = format!("SELECT {} FROM {}", select_cols, table_sql);

    let mut stmt = conn
        .prepare(&select_sql)
        .with_context(|| format!("Failed to prepare SELECT for DuckDB table '{}'", table))?;
    let mut rows = stmt
        .query([])
        .with_context(|| format!("Failed to query DuckDB table '{}'", table))?;

    // Step 3: stream rows in chunks, just like the CSV/TSV path.
    let mut chunk: Vec<HashMap<String, String>> = Vec::with_capacity(chunk_size);
    let source_str = format!("{}#{}", db_path.display(), table);
    // DuckDB has no header row; the first data row is row 1.
    let mut next_row_num = 1usize;

    while let Some(row) = rows
        .next()
        .with_context(|| format!("Failed to fetch row from DuckDB table '{}'", table))?
    {
        let mut map: HashMap<String, String> = HashMap::with_capacity(column_names.len());
        for (i, col_name) in column_names.iter().enumerate() {
            // NULL → None → empty string
            let val: Option<String> = row.get(i).with_context(|| {
                format!("Failed to read column '{}' from DuckDB table '{}'", col_name, table)
            })?;
            map.insert(col_name.clone(), val.unwrap_or_default());
        }
        chunk.push(map);

        if chunk.len() >= chunk_size {
            let chunk_start = next_row_num;
            next_row_num += chunk.len();
            flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                        use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                        &source_str, chunk_start)?;
            chunk.clear();
        }
    }
    if !chunk.is_empty() {
        let chunk_start = next_row_num;
        flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                    use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                    &source_str, chunk_start)?;
    }

    Ok(())
}

/// Quote a single SQL identifier with double quotes, escaping embedded quotes.
#[cfg(any(feature = "duckdb", feature = "sqlite"))]
fn quote_ident(s: &str) -> String {
    format!("\"{}\"", s.replace('"', "\"\""))
}

/// Quote a possibly schema-qualified identifier such as `myschema.mytable`,
/// quoting each dot-separated segment independently.
#[cfg(any(feature = "duckdb", feature = "sqlite"))]
fn quote_qualified_ident(s: &str) -> String {
    s.split('.')
        .map(quote_ident)
        .collect::<Vec<_>>()
        .join(".")
}

// ─── SQLite streaming reader ──────────────────────────────────────

/// Stream rows from a SQLite table, casting every column to TEXT in SQL so
/// the engine receives uniform string values regardless of storage class.
/// NULL values become empty strings (matching the convention of empty TSV cells).
#[cfg(feature = "sqlite")]
fn process_sqlite_table<W: Write>(
    db_path: &Path,
    table: &str,
    sub_config: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    name_maps: &jsonld::NameMaps,
    chunk_size: usize,
    dedup_limit: usize,
    use_oxrdf: bool,
    out_mode: ConvertMode,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
) -> Result<()> {
    let conn = rusqlite::Connection::open(db_path)
        .with_context(|| format!("Failed to open SQLite file: {}", db_path.display()))?;

    let table_sql = quote_qualified_ident(table);

    // Step 1: get column names by preparing a zero-row SELECT and reading the
    // statement's column metadata. Cheaper than PRAGMA table_info and works
    // for views as well as base tables.
    let column_names: Vec<String> = {
        let stmt = conn
            .prepare(&format!("SELECT * FROM {} LIMIT 0", table_sql))
            .with_context(|| format!("Failed to inspect SQLite table '{}'", table))?;
        stmt.column_names().iter().map(|s| s.to_string()).collect()
    };

    if column_names.is_empty() {
        bail!("SQLite table '{}' has no columns", table);
    }

    // Step 2: build SELECT with explicit TEXT casts, aliasing each column back
    // to its original name so the downstream engine sees the proper headers.
    let select_cols = column_names
        .iter()
        .map(|c| format!("CAST({col} AS TEXT) AS {col}", col = quote_ident(c)))
        .collect::<Vec<_>>()
        .join(", ");
    let select_sql = format!("SELECT {} FROM {}", select_cols, table_sql);

    let mut stmt = conn
        .prepare(&select_sql)
        .with_context(|| format!("Failed to prepare SELECT for SQLite table '{}'", table))?;
    let mut rows = stmt
        .query([])
        .with_context(|| format!("Failed to query SQLite table '{}'", table))?;

    // Step 3: stream rows in chunks, just like the CSV/TSV path.
    let mut chunk: Vec<HashMap<String, String>> = Vec::with_capacity(chunk_size);
    let source_str = format!("{}#{}", db_path.display(), table);
    // SQLite has no header row; the first data row is row 1.
    let mut next_row_num = 1usize;

    while let Some(row) = rows
        .next()
        .with_context(|| format!("Failed to fetch row from SQLite table '{}'", table))?
    {
        let mut map: HashMap<String, String> = HashMap::with_capacity(column_names.len());
        for (i, col_name) in column_names.iter().enumerate() {
            // NULL → None → empty string
            let val: Option<String> = row.get(i).with_context(|| {
                format!("Failed to read column '{}' from SQLite table '{}'", col_name, table)
            })?;
            map.insert(col_name.clone(), val.unwrap_or_default());
        }
        chunk.push(map);

        if chunk.len() >= chunk_size {
            let chunk_start = next_row_num;
            next_row_num += chunk.len();
            flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                        use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                        &source_str, chunk_start)?;
            chunk.clear();
        }
    }
    if !chunk.is_empty() {
        let chunk_start = next_row_num;
        flush_chunk(&chunk, sub_config, model, prefixes, name_maps,
                    use_oxrdf, out_mode, writer, first_subject, seen, dedup_limit,
                    &source_str, chunk_start)?;
    }

    Ok(())
}

// ─── chunk flushing (unified) ─────────────────────────────────────

fn flush_chunk<W: Write>(
    rows: &[HashMap<String, String>],
    convert: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    name_maps: &jsonld::NameMaps,
    use_oxrdf: bool,
    out_mode: ConvertMode,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
    dedup_limit: usize,
    source_path: &str,
    start_row: usize,
) -> Result<()> {
    let (triples, convert_subjects) = engine::process_rows(
        rows, convert, model, prefixes, source_path, start_row,
    ).with_context(|| "Failed to process rows")?;
    let unique = dedup_triples(triples, seen, dedup_limit);

    // oxrdf serves as a per-triple validation pass (filter out triples whose
    // IRIs oxrdf rejects); the actual serialization is done below.
    let validated: Vec<Triple> = if use_oxrdf {
        turtle_oxrdf::filter_type_only_subjects(&unique, &convert_subjects)
            .into_iter()
            .filter(|t| turtle_oxrdf::to_oxrdf_triple(t, prefixes).is_some())
            .collect()
    } else {
        unique
    };

    match out_mode {
        ConvertMode::Turtle => {
            turtle_native::write_triples(
                writer, &validated, prefixes, first_subject, &convert_subjects,
            )?;
        }
        ConvertMode::NTriples => {
            // N-Triples lines are self-contained, so this writer needs
            // neither `first_subject` nor any inter-chunk state.
            ntriples::write_triples(
                writer, &validated, prefixes, &convert_subjects,
            )?;
        }
        ConvertMode::JsonLd => {
            jsonld::write_triples(
                writer, &validated, prefixes, name_maps, first_subject,
                &convert_subjects, jsonld::JsonLdMode::Graph,
            )?;
        }
        ConvertMode::JsonLines => {
            jsonld::write_triples(
                writer, &validated, prefixes, name_maps, first_subject,
                &convert_subjects, jsonld::JsonLdMode::Lines,
            )?;
        }
        // `:context` returns early in `main` and never streams rows.
        ConvertMode::Context => unreachable!(
            "ConvertMode::Context is handled in main() and never reaches flush_chunk"
        ),
    }

    Ok(())
}

// ─── triple deduplication (bounded) ───────────────────────────────

fn hash_triple(t: &Triple) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    t.subject.hash(&mut h);
    t.predicate.hash(&mut h);
    match &t.object {
        RdfTerm::Uri(s)            => { 0u8.hash(&mut h); s.hash(&mut h); }
        RdfTerm::Curie(s)         => { 1u8.hash(&mut h); s.hash(&mut h); }
        RdfTerm::BlankNode(s)     => { 7u8.hash(&mut h); s.hash(&mut h); }
        RdfTerm::LiteralString(s) => { 2u8.hash(&mut h); s.hash(&mut h); }
        RdfTerm::LiteralInteger(i) => { 3u8.hash(&mut h); i.hash(&mut h); }
        RdfTerm::LiteralFloat(s)  => { 4u8.hash(&mut h); s.hash(&mut h); }
        RdfTerm::LiteralBoolean(b) => { 8u8.hash(&mut h); b.hash(&mut h); }
        RdfTerm::LiteralLangString(s, l) => { 5u8.hash(&mut h); s.hash(&mut h); l.hash(&mut h); }
        RdfTerm::LiteralDatatype(s, d)   => { 6u8.hash(&mut h); s.hash(&mut h); d.hash(&mut h); }
    }
    h.finish()
}

fn dedup_triples(triples: Vec<Triple>, seen: &mut HashSet<u64>, dedup_limit: usize) -> Vec<Triple> {
    if dedup_limit == 0 {
        return triples;
    }
    triples.into_iter().filter(|t| {
        let h = hash_triple(t);
        if seen.contains(&h) {
            return false;
        }
        if seen.len() < dedup_limit {
            seen.insert(h);
        }
        true
    }).collect()
}

// ─── shared helpers ───────────────────────────────────────────────

fn record_to_row(record: &csv::StringRecord, headers: &[String]) -> HashMap<String, String> {
    let mut row = HashMap::new();
    for (i, field) in record.iter().enumerate() {
        if i < headers.len() {
            row.insert(headers[i].clone(), field.to_string());
        }
    }
    row
}
