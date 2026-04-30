#![allow(dead_code)]

mod types;
mod prefix;
mod model;
mod convert;
mod engine;
mod turtle_oxrdf;
mod turtle_native;

use anyhow::{Context, Result, bail};
use clap::Parser;
use indexmap::IndexMap;
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::types::*;

#[derive(Parser, Debug)]
#[command(name = "table2turtle")]
#[command(about = "Convert TSV/CSV table data to RDF Turtle format")]
struct Cli {
    /// Path to the configuration folder containing model.yaml, prefix.yaml, convert.yaml
    #[arg(long)]
    config: PathBuf,

    /// Conversion format (currently only :turtle is supported)
    #[arg(long, default_value = ":turtle")]
    convert: String,

    /// Number of TSV rows to process per chunk (controls memory usage)
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

    /// Optional: input TSV file path or directory.
    /// - File: overrides all source() in convert.yaml
    /// - Directory: resolves source() paths relative to this directory
    /// - Omitted: uses source() paths from convert.yaml as-is
    input: Option<PathBuf>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.convert != ":turtle" {
        bail!("Only :turtle conversion format is currently supported");
    }
    if cli.serializer != "oxrdf" && cli.serializer != "native" {
        bail!("--serializer must be \"oxrdf\" or \"native\"");
    }

    // Load configuration files
    let config_dir = &cli.config;
    let prefixes = prefix::parse_prefix_yaml(&config_dir.join("prefix.yaml"))
        .with_context(|| "Failed to parse prefix.yaml")?;
    let model_def = model::parse_model_yaml(&config_dir.join("model.yaml"), &prefixes)
        .with_context(|| "Failed to parse model.yaml")?;
    let convert_config = convert::parse_convert_yaml(&config_dir.join("convert.yaml"))
        .with_context(|| "Failed to parse convert.yaml")?;

    let chunk_size = cli.chunk_size.max(1);
    let dedup_limit = cli.dedup_limit;
    let use_oxrdf = cli.serializer == "oxrdf";

    // ── Group subject rules by source file ──
    let source_groups = group_rules_by_source(&convert_config, cli.input.as_deref())?;

    // ── Set up shared output state ──
    let stdout = io::stdout();
    let mut buf_writer = BufWriter::new(stdout.lock());
    turtle_native::write_prefixes(&mut buf_writer, &prefixes)?;

    let mut first_subject = true;
    let mut seen: HashSet<u64> = HashSet::new();

    // ── Process each source file with its associated rules ──
    for (source_path, rule_indices) in &source_groups {
        // Build a sub-ConvertConfig containing only the rules for this source
        let sub_config = ConvertConfig {
            subject_rules: rule_indices.iter()
                .map(|&i| convert_config.subject_rules[i].clone())
                .collect(),
        };

        process_source_file(
            source_path, &sub_config, &model_def, &prefixes,
            chunk_size, dedup_limit, use_oxrdf,
            &mut buf_writer, &mut first_subject, &mut seen,
        ).with_context(|| format!("Failed processing source: {}", source_path.display()))?;
    }

    buf_writer.flush()?;
    Ok(())
}

// ─── source file grouping ─────────────────────────────────────────

/// Group subject rule indices by their resolved source file path.
/// Preserves first-appearance order of source files.
///
/// Resolution logic:
/// - `input` is a file   → ALL rules use that file (source() is ignored)
/// - `input` is a dir    → each rule's source() is resolved relative to it
/// - `input` is None     → each rule's source() is used as-is
/// - Rules without source() inherit the first source() found, or error
fn group_rules_by_source(
    config: &ConvertConfig,
    input: Option<&Path>,
) -> Result<IndexMap<PathBuf, Vec<usize>>> {
    // If input is a regular file, all rules share it
    if let Some(path) = input {
        if path.is_file() {
            let indices: Vec<usize> = (0..config.subject_rules.len()).collect();
            let mut map = IndexMap::new();
            map.insert(path.to_path_buf(), indices);
            return Ok(map);
        }
    }

    // Resolve base directory (if input is a dir)
    let base_dir: Option<&Path> = match input {
        Some(p) if p.is_dir() => Some(p),
        _ => None,
    };

    // Find the first source() as fallback for rules without one
    let default_source: Option<PathBuf> = config.subject_rules.iter()
        .find_map(|r| r.source_path.as_ref())
        .map(|s| resolve_source_path(s, base_dir));

    let mut groups: IndexMap<PathBuf, Vec<usize>> = IndexMap::new();

    for (i, rule) in config.subject_rules.iter().enumerate() {
        let path = if let Some(ref src) = rule.source_path {
            resolve_source_path(src, base_dir)
        } else if let Some(ref ds) = default_source {
            ds.clone()
        } else {
            bail!("Rule '{}' has no source() and no input file specified", rule.name);
        };

        groups.entry(path).or_default().push(i);
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

// ─── per-source-file processing ───────────────────────────────────

fn process_source_file<W: Write>(
    source_path: &Path,
    sub_config: &ConvertConfig,
    model: &Model,
    prefixes: &PrefixMap,
    chunk_size: usize,
    dedup_limit: usize,
    use_oxrdf: bool,
    writer: &mut W,
    first_subject: &mut bool,
    seen: &mut HashSet<u64>,
) -> Result<()> {
    let mut csv_reader = csv::ReaderBuilder::new()
        .delimiter(b'\t')
        .has_headers(true)
        .flexible(true)
        .from_path(source_path)
        .with_context(|| format!("Failed to open TSV file: {}", source_path.display()))?;

    let headers: Vec<String> = csv_reader.headers()
        .with_context(|| "Failed to read TSV headers")?
        .iter()
        .map(|h| h.to_string())
        .collect();

    let mut chunk: Vec<HashMap<String, String>> = Vec::with_capacity(chunk_size);
    let source_str = source_path.display().to_string();
    // Header is row 1; first data row is row 2
    let mut next_row_num = 2usize;

    for result in csv_reader.records() {
        let record = result.with_context(|| "Failed to read TSV record")?;
        chunk.push(record_to_row(&record, &headers));

        if chunk.len() >= chunk_size {
            let chunk_start = next_row_num;
            next_row_num += chunk.len();
            flush_chunk(&chunk, sub_config, model, prefixes,
                        use_oxrdf, writer, first_subject, seen, dedup_limit,
                        &source_str, chunk_start)?;
            chunk.clear();
        }
    }
    if !chunk.is_empty() {
        let chunk_start = next_row_num;
        flush_chunk(&chunk, sub_config, model, prefixes,
                    use_oxrdf, writer, first_subject, seen, dedup_limit,
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
    use_oxrdf: bool,
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

    if use_oxrdf {
        let validated: Vec<Triple> = turtle_oxrdf::filter_type_only_subjects(&unique, &convert_subjects)
            .into_iter()
            .filter(|t| turtle_oxrdf::to_oxrdf_triple(t, prefixes).is_some())
            .collect();
        turtle_native::write_triples(writer, &validated, prefixes, first_subject, &convert_subjects)?;
    } else {
        turtle_native::write_triples(writer, &unique, prefixes, first_subject, &convert_subjects)?;
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
