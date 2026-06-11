//! Streaming JSON-LD writer.
//!
//! Output shape — each model.yaml subject name is reserved as an `@id`
//! keyword alias, and each object name maps to its predicate IRI. Object
//! names get one of three binding forms in `@context` depending on the
//! model's `value_type`: a plain string binding for self-describing
//! literals, an `@type: @id` coercion for URI-valued objects, or an
//! `@type: <datatype>` coercion for typed literals — both of the latter
//! lift type information out of `@graph` so individual values can be bare
//! scalars:
//! ```json
//! {
//!   "@context": {
//!     "id": "@id",                  // generic fallback (object refs, bnodes)
//!     "rdf": "...",                 // prefix bindings (from prefix.yaml)
//!     "foaf": "...",
//!     "xsd": "...",
//!     "Person": "@id",              // per-subject @id aliases
//!     "fullName": "foaf:name",       // plain object binding (literal value)
//!     "knows": {                     // @id-typed binding (URI value)
//!       "@id": "foaf:knows",
//!       "@type": "@id"
//!     },
//!     "displayName": {               // datatype-typed binding (typed literal)
//!       "@id": "bp3:displayName",
//!       "@type": "xsd:string"
//!     }
//!   },
//!   "@graph": [
//!     {
//!       "Person": "ex:p1",
//!       "@type": "foaf:Person",
//!       "fullName": "John",
//!       "knows": "ex:p2",             // bare string, NOT {"id": "ex:p2"}
//!       "displayName": "John Doe"     // bare string, NOT {"@value": ..., "@type": ...}
//!     }
//!   ]
//! }
//! ```
//!
//! Rules:
//!   * Subject identifier key: `triple.subject_name` when that name was
//!     registered as an `@id` alias in `NameMaps`; otherwise the `ID_ALIAS`
//!     fallback (used for auto-generated subjects whose name collided with
//!     a prefix and was skipped).
//!   * Predicate JSON key: `triple.object_name` (an ObjectDef.name from
//!     model.yaml) when present, with a compact IRI fallback.
//!   * Object value rendering: when the predicate's `@context` binding
//!     coerces the value type (either `@type: @id` for URIs or
//!     `@type: <datatype>` for typed literals matching the binding), the
//!     value is emitted as a bare scalar string. URI values without a
//!     coercion are wrapped as `{"id": ref}`; typed literals whose datatype
//!     differs from the binding keep their explicit `{"@value": ..., "@type": ...}`.
//!     Plain literals, lang strings, and inlined blank nodes are unaffected.
//!   * `@type` value: a compact IRI / CURIE. Subject names cannot be reused
//!     here because each one is bound to `@id` in `@context`.
//!
//! Filtering behavior matches `turtle_native::write_triples`:
//!   * type-only convert subjects are dropped (together with references to them),
//!   * blank-node subjects are inlined into their parents.
//!
//! Output modes (selected by `--convert`):
//!   * `:jsonld` — the single enclosing document shown above
//!     (`write_prelude` + `write_triples(JsonLdMode::Graph)` + `write_postlude`).
//!   * `:jsonl` — JSON Lines for Elasticsearch: one document per line, each
//!     carrying `"@context": "context.jsonld"` instead of the inline
//!     context. A subject with a repeated (array-valued) property is
//!     exploded so each repeated child becomes its own document
//!     (`write_triples(JsonLdMode::Lines)`, no prelude/postlude).
//!   * `:context` — just the `{ "@context": { ... } }` document, written by
//!     `write_context_document`, suitable for saving as `context.jsonld`.

use std::collections::HashSet;
use std::io::Write;
use indexmap::IndexMap;
use serde_json::{json, Map, Value};

use crate::types::*;

/// JSON-LD keyword alias for `@id`. Declared once in `@context` so graph
/// nodes can use this short, unprefixed key instead of the reserved `@id`.
/// Changing this constant updates every reference site (context entry,
/// subject `@id` field, object references, blank-node fallbacks).
const ID_ALIAS: &str = "id";

/// Filename written into the `"@context"` field of every node in JSON Lines
/// mode (`"@context": "context.jsonld"`). It is a *reference* to an external
/// context document — the one produced by `--convert :context` — rather than
/// an inline context object, so each line stays small and self-contained.
const CONTEXT_REF: &str = "context.jsonld";

/// Which JSON-LD shape `write_triples` emits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JsonLdMode {
    /// One enclosing document: `{ "@context": {...}, "@graph": [ <nodes> ] }`.
    /// Nodes are pretty-printed and comma-separated; the surrounding
    /// `@context` / `@graph` scaffolding is emitted by `write_prelude` and
    /// `write_postlude`.
    Graph,
    /// JSON Lines for Elasticsearch: every emitted document is a
    /// self-contained JSON object on its own line, carrying
    /// `"@context": "context.jsonld"` as its first key. A subject with a
    /// repeated (array-valued) property is exploded via `explode_node` so
    /// each repeated child becomes its own line. There is no enclosing
    /// document and no `write_prelude` / `write_postlude`; the matching
    /// context document is produced separately by `write_context_document`.
    Lines,
}

// ─── name-mapping precomputation ──────────────────────────────────

/// Shape of a single `@context` entry for an object name.
///
/// Three forms are produced from `ObjectValueType`:
///   * `Plain` — `"name": "<pred>"`. Used for literals whose JSON
///     representation is self-describing (string, integer, boolean, float).
///   * `IdTyped` — `"name": {"@id": "<pred>", "@type": "@id"}`. Used for
///     URI-valued objects (`Uri`, `Reference`, `ReferenceList`); allows
///     `@graph` to emit bare strings interpreted as IRI references.
///   * `Typed` — `"name": {"@id": "<pred>", "@type": "<datatype>"}`. Used
///     for `LiteralDatatype` objects; lifts the datatype out of each value
///     into the context, so `@graph` emits bare strings interpreted as
///     literals of that type.
#[derive(Debug, Clone)]
pub enum ObjectBinding {
    /// `"object_name": "<predicate IRI>"`
    Plain(String),
    /// `"object_name": { "@id": "<predicate IRI>", "@type": "@id" }`
    IdTyped(String),
    /// `"object_name": { "@id": "<predicate IRI>", "@type": "<datatype>" }`
    /// The datatype is stored in its raw model form (a CURIE like
    /// `xsd:string` or a full IRI) and rendered through `compact_iri` at
    /// emit time.
    Typed { pred: String, datatype: String },
}

impl ObjectBinding {
    /// Decide which binding form an object should get from its model value_type.
    /// The "first ObjectDef with this name wins" rule is enforced in
    /// `NameMaps::from_model` by skipping subsequent inserts.
    fn from_value_type(value_type: &ObjectValueType, pred_uri: &str) -> Self {
        match value_type {
            ObjectValueType::Uri
            | ObjectValueType::Reference(_)
            | ObjectValueType::ReferenceList(_) => Self::IdTyped(pred_uri.to_string()),
            ObjectValueType::LiteralDatatype { datatype } => Self::Typed {
                pred: pred_uri.to_string(),
                datatype: datatype.clone(),
            },
            _ => Self::Plain(pred_uri.to_string()),
        }
    }

    /// The datatype IRI declared for this binding, if any. Used by
    /// `term_to_json` to decide whether a `LiteralDatatype` runtime value
    /// matches the binding (and can be emitted as a bare string) or
    /// conflicts with it (and must keep its explicit `@type` per-value).
    fn typed_datatype(&self) -> Option<&str> {
        match self {
            Self::Typed { datatype, .. } => Some(datatype.as_str()),
            _ => None,
        }
    }
}

/// Lookup tables derived from the Model so `jsonld` can substitute friendly
/// names for IRIs at write time without re-scanning the model on every triple.
///
/// Each entry here corresponds to a single `@context` binding declared in
/// `write_prelude`. There is no longer a `subject_name → rdf_type` mapping:
/// every subject name is reserved as an `@id` alias so it can serve as the
/// subject-identifier key in graph nodes.
pub struct NameMaps {
    /// Subject names that appear in `@context` as `"<name>": "@id"` aliases.
    /// Used at write time to confirm a triple's `subject_name` was actually
    /// registered (and isn't shadowed by a prefix collision); when it was,
    /// `build_named_node` emits the subject identifier under that name.
    pub subject_id_aliases: HashSet<String>,
    /// object_name → binding (plain predicate IRI, or `@type: @id` coerced).
    /// The binding form drives both the `@context` shape and how `@graph`
    /// values are rendered for that key.
    pub object_name_to_binding: IndexMap<String, ObjectBinding>,
    /// Subject names in model order, preserved for stable `@context` output.
    pub subject_aliases_ordered: Vec<String>,
    /// Prefix names that an object binding has taken over. An object name is
    /// allowed to collide with a prefix — the object binding wins — but a
    /// JSON object cannot carry the same key twice, so the prefix of that
    /// name must be dropped from `@context`. The writer also avoids
    /// compacting IRIs through these prefixes (the namespace meaning of the
    /// name is gone), emitting full IRIs instead so values still resolve.
    pub shadowed_prefixes: HashSet<String>,
}

impl NameMaps {
    /// Build name lookups from the Model.
    ///
    /// `@context` is a single namespace shared by prefixes, the `ID_ALIAS`
    /// fallback, per-subject `@id` aliases, and per-object bindings, so name
    /// clashes must be resolved to one winner per name:
    ///   * A *subject* name that clashes with the `ID_ALIAS` or a prefix is
    ///     skipped (it falls back to the `ID_ALIAS` key at write time).
    ///   * An *object* name that clashes with a prefix instead *wins*: it is
    ///     registered as a binding and the prefix is recorded in
    ///     `shadowed_prefixes` so the writer drops it. An object name that
    ///     clashes with `ID_ALIAS` or a subject alias is still skipped.
    pub fn from_model(model: &Model, prefixes: &PrefixMap) -> Self {
        let collides_with_reserved = |name: &str| -> bool {
            name == ID_ALIAS || prefixes.contains_key(name)
        };

        // Pass 1: pick subject names that will become @id aliases.
        let mut subject_aliases_ordered: Vec<String> = Vec::new();
        let mut subject_id_aliases: HashSet<String> = HashSet::new();
        for subject in &model.subjects {
            if collides_with_reserved(&subject.name) {
                continue;
            }
            if subject_id_aliases.insert(subject.name.clone()) {
                subject_aliases_ordered.push(subject.name.clone());
            }
        }

        // Pass 2: register object names. An object name is allowed to
        // collide with a *prefix*: the object binding wins and the prefix of
        // the same name is shadowed (recorded in `shadowed_prefixes`, then
        // dropped from `@context` and from IRI compaction by the writer).
        // This lets an object such as `ncbigene` — which shares its name
        // with the `ncbigene:` prefix — get its own `@context` term
        // `{"@id": "rdfs:seeAlso", "@type": "@id"}` and be used directly as
        // the JSON key, instead of falling back to the bare predicate IRI.
        //
        // Collisions with `ID_ALIAS` or a subject `@id` alias are still
        // skipped: those genuinely share the term namespace with no safe
        // winner. The binding form comes from the ObjectDef's value_type, so
        // URI-valued objects get the `@type: @id` coercion. `leaf_objects()`
        // recurses through nested blank nodes, so deeply-nested objects are
        // registered too, each paired with the predicate that attaches it.
        let mut object_name_to_binding: IndexMap<String, ObjectBinding> = IndexMap::new();
        let mut shadowed_prefixes: HashSet<String> = HashSet::new();
        let collides = |name: &str| -> bool {
            name == ID_ALIAS || subject_id_aliases.contains(name)
        };
        for subject in &model.subjects {
            for (obj, pred_uri) in subject.leaf_objects() {
                if collides(&obj.name) {
                    continue;
                }
                object_name_to_binding
                    .entry(obj.name.clone())
                    .or_insert_with(|| ObjectBinding::from_value_type(&obj.value_type, pred_uri));
                // The object binding takes the term namespace; if a prefix
                // of the same name exists it is now shadowed.
                if prefixes.contains_key(&obj.name) {
                    shadowed_prefixes.insert(obj.name.clone());
                }
            }
        }

        Self {
            subject_id_aliases,
            object_name_to_binding,
            subject_aliases_ordered,
            shadowed_prefixes,
        }
    }
}

// ─── prelude / postlude ────────────────────────────────────────────

/// Build the effective prefix map for serialization: the declared prefixes
/// minus any whose name an object binding has taken over
/// (`NameMaps::shadowed_prefixes`).
///
/// A shadowed name resolves to an object term in `@context`, not to a
/// namespace, so it must neither be emitted as a prefix binding nor used to
/// compact IRIs — an IRI compacted through a shadowed prefix would be
/// re-read by a JSON-LD processor as that object's predicate. Passing this
/// map (instead of the raw prefix table) through every writer keeps
/// `@context` and `@graph` consistent: IRIs in a shadowed namespace are
/// simply written out in full `http://…` form.
fn effective_prefixes(prefixes: &PrefixMap, names: &NameMaps) -> PrefixMap {
    if names.shadowed_prefixes.is_empty() {
        return prefixes.clone();
    }
    prefixes
        .iter()
        .filter(|(name, _)| !names.shadowed_prefixes.contains(name.as_str()))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}

/// Build the ordered list of `@context` entries from the prefix table and
/// the precomputed name maps.
///
/// Context layout (one entry per logical binding):
///   1. `ID_ALIAS` fallback (used by object refs and bnode fallbacks)
///   2. Prefix bindings
///   3. Per-subject `@id` aliases (each subject name → `"@id"`)
///   4. Object-name bindings (scalar, `@id`-coerced, or datatype-coerced)
///
/// Shared by `write_prelude` (the inline `@context` of the `@graph`
/// document) and `write_context_document` (the standalone `:context` file),
/// so both forms always carry exactly the same bindings.
fn build_context_entries(prefixes: &PrefixMap, names: &NameMaps) -> Vec<ContextEntry> {
    let mut entries: Vec<ContextEntry> = Vec::new();
    entries.push(ContextEntry::Scalar(ID_ALIAS.to_string(), "@id".to_string()));
    for (prefix, uri) in prefixes {
        entries.push(ContextEntry::Prefix {
            name: prefix.clone(),
            iri: uri.clone(),
            explicit: prefix_needs_explicit_flag(uri),
        });
    }
    for name in &names.subject_aliases_ordered {
        entries.push(ContextEntry::Scalar(name.clone(), "@id".to_string()));
    }
    for (name, binding) in &names.object_name_to_binding {
        match binding {
            ObjectBinding::Plain(pred) => {
                entries.push(ContextEntry::Scalar(name.clone(), pred.clone()));
            }
            ObjectBinding::IdTyped(pred) => {
                entries.push(ContextEntry::Object {
                    key: name.clone(),
                    pred: pred.clone(),
                    type_value: "@id".to_string(),
                });
            }
            ObjectBinding::Typed { pred, datatype } => {
                // The datatype is stored as it appeared in model.yaml (a
                // CURIE or a full IRI); compact it against the current
                // prefix table so the `@type` slot matches how the rest of
                // the document refers to that IRI.
                entries.push(ContextEntry::Object {
                    key: name.clone(),
                    pred: pred.clone(),
                    type_value: compact_iri(datatype, prefixes),
                });
            }
        }
    }
    entries
}

/// Write the `"@context": { ... }` block (the key and its object value),
/// indented to sit two spaces inside an enclosing object.
///
/// `trailing_comma` controls whether the closing `}` is followed by a comma:
/// `true` when another key follows (`@graph`, in `write_prelude`), `false`
/// when `@context` is the only/last key (in `write_context_document`).
fn write_context_block<W: Write>(
    writer: &mut W,
    entries: &[ContextEntry],
    trailing_comma: bool,
) -> std::io::Result<()> {
    writeln!(writer, "  \"@context\": {{")?;
    let n = entries.len();
    for (i, entry) in entries.iter().enumerate() {
        let comma = if i + 1 < n { "," } else { "" };
        match entry {
            ContextEntry::Scalar(k, v) => {
                writeln!(writer, "    {}: {}{}", json_string(k), json_string(v), comma)?;
            }
            ContextEntry::Object { key, pred, type_value } => {
                // Multi-line form for readability:
                //     "objName": {
                //       "@id": "ex:pred",
                //       "@type": "@id"          // or "xsd:string", etc.
                //     },
                writeln!(writer, "    {}: {{", json_string(key))?;
                writeln!(writer, "      \"@id\": {},", json_string(pred))?;
                writeln!(writer, "      \"@type\": {}", json_string(type_value))?;
                writeln!(writer, "    }}{}", comma)?;
            }
            ContextEntry::Prefix { name, iri, explicit } => {
                if *explicit {
                    // IRI doesn't end in a gen-delim → JSON-LD 1.1 needs an
                    // explicit "@prefix": true to treat this as a prefix:
                    //     "cclec": {
                    //       "@id": "https://...?cell_line=",
                    //       "@prefix": true
                    //     },
                    writeln!(writer, "    {}: {{", json_string(name))?;
                    writeln!(writer, "      \"@id\": {},", json_string(iri))?;
                    writeln!(writer, "      \"@prefix\": true")?;
                    writeln!(writer, "    }}{}", comma)?;
                } else {
                    // IRI ends in a gen-delim → the plain scalar form is
                    // recognized as a prefix automatically.
                    writeln!(writer, "    {}: {}{}", json_string(name), json_string(iri), comma)?;
                }
            }
        }
    }
    if trailing_comma {
        writeln!(writer, "  }},")?;
    } else {
        writeln!(writer, "  }}")?;
    }
    Ok(())
}

/// Write the JSON-LD prelude: opens the top-level object, emits `@context`
/// containing prefix bindings, per-subject `@id` aliases, and per-object
/// bindings (some of which may carry an explicit `@type: @id` coercion),
/// and opens the `@graph` array.
///
/// Used only by `JsonLdMode::Graph`. JSON Lines output has no prelude.
pub fn write_prelude<W: Write>(
    writer: &mut W,
    prefixes: &PrefixMap,
    names: &NameMaps,
) -> std::io::Result<()> {
    let prefixes = &effective_prefixes(prefixes, names);
    let entries = build_context_entries(prefixes, names);
    writeln!(writer, "{{")?;
    write_context_block(writer, &entries, true)?;
    writeln!(writer, "  \"@graph\": [")?;
    Ok(())
}

/// Write a standalone JSON-LD context document: `{ "@context": { ... } }`.
///
/// Emitted by `--convert :context`. The `@context` body is byte-for-byte the
/// same one `write_prelude` embeds in the `@graph` document; pulling it into
/// its own file lets it be saved as `context.jsonld` and referenced by the
/// `"@context": "context.jsonld"` strings that `JsonLdMode::Lines` writes
/// onto every node.
pub fn write_context_document<W: Write>(
    writer: &mut W,
    prefixes: &PrefixMap,
    names: &NameMaps,
) -> std::io::Result<()> {
    let prefixes = &effective_prefixes(prefixes, names);
    let entries = build_context_entries(prefixes, names);
    writeln!(writer, "{{")?;
    write_context_block(writer, &entries, false)?;
    writeln!(writer, "}}")?;
    Ok(())
}

/// A single `@context` line to emit. Used only by `write_prelude` to keep
/// the different binding shapes on separate code paths without rebuilding
/// the formatting decision tree inline.
enum ContextEntry {
    /// `"key": "value"`
    Scalar(String, String),
    /// `"key": { "@id": "<pred>", "@type": "<type_value>" }`.
    /// `type_value` is the raw `@type` slot text: `"@id"` for URI coercion,
    /// or a datatype CURIE/IRI (e.g. `"xsd:string"`) for typed literals.
    Object { key: String, pred: String, type_value: String },
    /// A namespace prefix binding.
    ///
    /// In JSON-LD 1.1 a term is only usable as a compact-IRI prefix
    /// (`prefix:local`) automatically when its IRI ends in a gen-delim
    /// character (`/ # : ? [ ] @`). When the IRI ends in anything else —
    /// e.g. `https://example.org/page?id=` ending in `=` — the term must
    /// carry an explicit `"@prefix": true` flag, which forces the expanded
    /// object form:
    /// ```json
    /// "cclec": { "@id": "https://...?cell_line=", "@prefix": true }
    /// ```
    /// `explicit` records which form is needed; when false the prefix is
    /// emitted as a plain `Scalar`-style `"name": "iri"` line.
    Prefix { name: String, iri: String, explicit: bool },
}

/// IRI gen-delim characters (RFC 3987). A prefix IRI ending in one of these
/// is recognized as a prefix automatically by JSON-LD 1.1; an IRI ending in
/// anything else needs an explicit `"@prefix": true`.
const GEN_DELIMS: [char; 7] = ['/', '#', ':', '?', '[', ']', '@'];

/// Decide whether a prefix IRI needs an explicit `"@prefix": true` flag.
///
/// Returns `true` (explicit flag required) when the IRI does NOT end in a
/// gen-delim character. An empty IRI is treated as not needing the flag —
/// it cannot meaningfully act as a prefix either way, so the simpler scalar
/// form is used.
fn prefix_needs_explicit_flag(iri: &str) -> bool {
    match iri.chars().next_back() {
        Some(last) => !GEN_DELIMS.contains(&last),
        None => false,
    }
}

/// Write the JSON-LD postlude: closes the `@graph` array and the top-level
/// object. `any_subjects` controls whether a trailing newline is added before
/// the closing `]` for visual consistency.
pub fn write_postlude<W: Write>(
    writer: &mut W,
    any_subjects: bool,
) -> std::io::Result<()> {
    if any_subjects {
        writeln!(writer)?;
    }
    writeln!(writer, "  ]")?;
    writeln!(writer, "}}")?;
    Ok(())
}

// ─── per-chunk writer ──────────────────────────────────────────────

/// Write one chunk of triples as JSON-LD.
///
/// `mode` selects the shape:
///   * `JsonLdMode::Graph` — each subject becomes a pretty-printed,
///     comma-separated entry of the enclosing `@graph` array.
///   * `JsonLdMode::Lines` — each subject becomes one or more compact JSON
///     objects, one per line, each prefixed with
///     `"@context": "context.jsonld"`. A subject carrying a repeated
///     (array-valued) property is exploded so each repeated child is its
///     own line — see `explode_node`.
///
/// Applies the same filtering as `turtle_native::write_triples`:
///   1. Convert-generated subjects with only `rdf:type` predicates are dropped,
///      together with any predicate–object pairs that reference them.
///   2. Blank-node subjects (starting with `_:`) are not emitted at the
///      top level — they are inlined into their parent.
///   3. Auto-generated subjects (not in `convert_subjects`) are always kept.
pub fn write_triples<W: Write>(
    writer: &mut W,
    triples: &[Triple],
    prefixes: &PrefixMap,
    names: &NameMaps,
    first_subject: &mut bool,
    convert_subjects: &HashSet<String>,
    mode: JsonLdMode,
) -> std::io::Result<()> {
    // Drop prefixes shadowed by an object binding so IRIs in those
    // namespaces are written in full form rather than as a compact IRI a
    // processor would re-expand through the (now object-term) name.
    let prefixes = &effective_prefixes(prefixes, names);
    let grouped = group_triples(triples);

    let type_only: HashSet<&str> = grouped.iter()
        .filter(|(subj, items)| {
            convert_subjects.contains(subj.as_str()) &&
                items.iter().all(|it| it.predicate == "a" || it.predicate == "rdf:type")
        })
        .map(|(subj, _)| subj.as_str())
        .collect();

    let bnode_subjects: HashSet<&str> = grouped.keys()
        .filter(|s| s.starts_with("_:"))
        .map(|s| s.as_str())
        .collect();

    for (subject, items) in &grouped {
        if type_only.contains(subject.as_str()) || bnode_subjects.contains(subject.as_str()) {
            continue;
        }

        let filtered: Vec<&TripleItem> = items.iter()
            .filter(|it| !is_type_only_ref(&it.object, &type_only))
            .collect();

        if filtered.is_empty() {
            continue;
        }

        let node = build_named_node(subject, &filtered, &grouped, prefixes, names, &type_only);

        match mode {
            JsonLdMode::Graph => {
                // Inside the `@graph` array: comma-separate consecutive
                // nodes and pretty-print each one indented under the array.
                if !*first_subject {
                    writeln!(writer, ",")?;
                }
                write_indented_value(writer, &node, 4)?;
            }
            JsonLdMode::Lines => {
                // JSON Lines for Elasticsearch: a subject that owns a
                // repeated child (e.g. a CCLE cell line with many
                // `m2r:variation`s) is exploded so each child becomes its
                // own document. `@context` is prepended to every line so
                // each parses as JSON-LD on its own against the external
                // context document.
                for doc in explode_node(node) {
                    let doc = prepend_context_ref(doc);
                    let line = serde_json::to_string(&doc)
                        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
                    writeln!(writer, "{}", line)?;
                }
            }
        }
        *first_subject = false;
    }

    Ok(())
}

/// Return `node` with `"@context": "context.jsonld"` inserted as its first
/// key. Used in JSON Lines mode so every emitted object is independently
/// parseable as JSON-LD against the external context document.
///
/// `serde_json::Map` is backed by `IndexMap` (the crate is built with the
/// `preserve_order` feature), so rebuilding the map front-to-back is what
/// guarantees `@context` lands ahead of every other key.
fn prepend_context_ref(node: Value) -> Value {
    match node {
        Value::Object(original) => {
            let mut m = Map::new();
            m.insert("@context".to_string(), Value::String(CONTEXT_REF.to_string()));
            for (k, v) in original {
                m.insert(k, v);
            }
            Value::Object(m)
        }
        // A non-object node is unexpected here (subjects always build objects)
        // but is passed through unchanged so the writer stays total.
        other => other,
    }
}

/// Explode a top-level node into one document per repeated child, for JSON
/// Lines / Elasticsearch output.
///
/// Elasticsearch indexes one document per line. A subject that owns a
/// repeated child — e.g. a CCLE cell line carrying many `m2r:variation`s —
/// is far more useful as one document *per child* than as a single document
/// holding a large array: each child becomes independently searchable,
/// filterable and scorable, and queries need not reach into arrays.
///
/// Rule: every key whose value is a JSON array is treated as a repeated
/// property and split out. `@type` is exempt — a multi-typed node keeps its
/// full `@type` array on every emitted line. Scalar / object properties are
/// copied unchanged onto every document. When a node has several array-valued
/// properties the cartesian product is produced, so each document still holds
/// exactly one value of every repeated property; a node with no array
/// property yields itself unchanged (a single document). An array-valued
/// property that happens to be empty contributes nothing and is simply
/// omitted from the emitted documents (rather than collapsing the product to
/// zero).
///
/// Only the *top level* is exploded: arrays nested inside an object value
/// (for instance a variation's own fields) are deliberately left intact, so
/// each child keeps its internal structure.
///
/// Original key order is preserved, so an exploded document has the same
/// field layout as the un-exploded node.
fn explode_node(node: Value) -> Vec<Value> {
    let Value::Object(map) = node else {
        // Subjects always build objects; anything else is passed through as
        // a single document so the function stays total.
        return vec![node];
    };

    // The repeated properties to split: array-valued, `@type` excepted.
    let array_keys: Vec<String> = map.iter()
        .filter(|(k, v)| k.as_str() != "@type" && v.is_array())
        .map(|(k, _)| k.clone())
        .collect();

    if array_keys.is_empty() {
        return vec![Value::Object(map)];
    }

    // Cartesian product of the array elements. Each `assignment` maps every
    // exploding key to the single element chosen for one output document.
    let mut assignments: Vec<Map<String, Value>> = vec![Map::new()];
    for key in &array_keys {
        let items = map.get(key).and_then(Value::as_array).cloned().unwrap_or_default();
        if items.is_empty() {
            // Empty array: no value to choose; the key is dropped entirely
            // instead of zeroing out the product.
            continue;
        }
        let mut next = Vec::with_capacity(assignments.len() * items.len());
        for base in &assignments {
            for item in &items {
                let mut a = base.clone();
                a.insert(key.clone(), item.clone());
                next.push(a);
            }
        }
        assignments = next;
    }

    // Re-emit one object per assignment, walking the original key order so
    // each document's field layout matches the un-exploded node.
    assignments.into_iter()
        .map(|assignment| {
            let mut m = Map::new();
            for (k, v) in &map {
                if let Some(chosen) = assignment.get(k) {
                    // Exploding key → the element picked for this document.
                    m.insert(k.clone(), chosen.clone());
                } else if !array_keys.contains(k) {
                    // Fixed (scalar / object / @type) property → copied through.
                    m.insert(k.clone(), v.clone());
                }
                // else: an exploding key whose array was empty → omitted.
            }
            Value::Object(m)
        })
        .collect()
}

// ─── node builders ─────────────────────────────────────────────────

/// Build a JSON-LD object for a named (non-blank) subject.
///
/// The subject identifier key is taken from the triple's `subject_name` when
/// that name was registered as an `@id` alias in `NameMaps`; this gives each
/// model.yaml subject its own labelled identifier (e.g. `"Person": "ex:p1"`).
/// When no usable `subject_name` is available — either the triple has none
/// (auto-generated subject), or the name collided with a prefix and was
/// skipped during `NameMaps::from_model` — the `ID_ALIAS` fallback is used
/// instead so the document still parses as JSON-LD.
fn build_named_node(
    subject: &str,
    items: &[&TripleItem],
    grouped: &IndexMap<String, Vec<TripleItem>>,
    prefixes: &PrefixMap,
    names: &NameMaps,
    type_only: &HashSet<&str>,
) -> Value {
    // Pick the @id key for this node. Any triple in the group will do since
    // engine.rs gives all triples sharing a subject the same subject_name.
    let id_key = items.iter()
        .find_map(|it| it.subject_name.as_deref())
        .filter(|n| names.subject_id_aliases.contains(*n))
        .map(|n| n.to_string())
        .unwrap_or_else(|| ID_ALIAS.to_string());

    let mut obj = Map::new();
    obj.insert(id_key, Value::String(compact_iri(subject, prefixes)));
    fill_predicates(&mut obj, items.iter().copied(), grouped, prefixes, names, type_only);
    Value::Object(obj)
}

/// Build a JSON-LD object for an inlined blank node. No `@id` is emitted.
fn build_blank_node(
    bnode_id: &str,
    grouped: &IndexMap<String, Vec<TripleItem>>,
    prefixes: &PrefixMap,
    names: &NameMaps,
    type_only: &HashSet<&str>,
) -> Value {
    if let Some(items) = grouped.get(bnode_id) {
        let refs: Vec<&TripleItem> = items.iter()
            .filter(|it| !is_type_only_ref(&it.object, type_only))
            .collect();
        let mut obj = Map::new();
        fill_predicates(&mut obj, refs.into_iter(), grouped, prefixes, names, type_only);
        Value::Object(obj)
    } else {
        // Unknown blank node in this chunk — emit as a bare id reference so
        // downstream tools can still link it across chunks.
        let mut m = Map::new();
        m.insert(ID_ALIAS.to_string(), Value::String(bnode_id.to_string()));
        Value::Object(m)
    }
}

/// Per-key coercion state derived from the `@context` binding for the
/// predicate group. `term_to_json` consults this to decide whether a value
/// can be emitted as a bare scalar (because the context will re-attach the
/// missing type info) or must carry its own `@id`/`@type` wrapper.
#[derive(Debug, Clone, Copy)]
enum TermCoercion<'a> {
    /// No `@context` coercion: emit `{"id": ref}` for URIs and explicit
    /// `{"@value": v, "@type": dt}` for typed literals.
    None,
    /// Context binds the predicate with `@type: @id`: URIs can be bare strings.
    Id,
    /// Context binds the predicate with `@type: <datatype>`: a `LiteralDatatype`
    /// whose datatype matches can be emitted as a bare string.
    Datatype(&'a str),
}

/// Insert predicates into a node object. Triples are grouped by the JSON key
/// they'll actually be emitted under, NOT by predicate alone — because
/// blank-node-group ObjectDefs in model.yaml routinely share an inner
/// predicate (e.g. `pair0` and `pair1` both ride on `obo:BFO_0000051`).
/// Grouping by predicate alone would collapse such siblings into one key
/// with an array of all their values, losing the per-ObjectDef structure.
///
/// Key selection:
///   * `rdf:type` / `a` → `@type`.
///   * Other triples → the triple's own `object_name` when present
///     (each ObjectDef gets its own key); otherwise a compact-IRI form of
///     the predicate as the fallback for triples engine didn't annotate.
///
/// Within each key's group, values keep their relative order. A single
/// value collapses to a scalar; multiple values become a JSON array.
fn fill_predicates<'a, I>(
    obj: &mut Map<String, Value>,
    items: I,
    grouped: &IndexMap<String, Vec<TripleItem>>,
    prefixes: &PrefixMap,
    names: &'a NameMaps,
    type_only: &HashSet<&str>,
)
where
    I: Iterator<Item = &'a TripleItem>,
{
    /// Per-key bucket: the items in declaration order plus the coercion
    /// state derived from the binding. All items in a bucket share an
    /// `object_name` and therefore share a binding, so the coercion is set
    /// once when the bucket is created.
    struct Bucket<'a> {
        items: Vec<&'a TripleItem>,
        coercion: TermCoercion<'a>,
    }

    // Group by the *output key*, preserving first-appearance order so the
    // emitted JSON keeps the same order as the input triples.
    let mut by_key: IndexMap<String, Bucket<'a>> = IndexMap::new();

    for it in items {
        let is_type = it.predicate == "a" || it.predicate == "rdf:type";

        let key = if is_type {
            "@type".to_string()
        } else if let Some(name) = it.object_name.as_deref()
            .filter(|n| names.object_name_to_binding.contains_key(*n))
        {
            // The object name is a registered `@context` binding, so a
            // JSON-LD processor will expand this key to the right predicate.
            name.to_string()
        } else {
            // Either the triple has no object name, or the name was dropped
            // from `@context` by `NameMaps::from_model` because it collided
            // with the id alias or a subject `@id` alias. (A collision with a
            // prefix does NOT land here — the object binding wins and the
            // prefix is shadowed.) Using an unregistered name as the key
            // would let a processor re-expand it through some other binding,
            // so fall back to a compact-IRI form of the predicate itself.
            format_predicate_key(&it.predicate, prefixes)
        };

        let coercion = if is_type {
            TermCoercion::None
        } else {
            // Look up the binding for this triple's object_name (if any) and
            // map it to a coercion. The lifetime here is the borrow of
            // `names`, which outlives the bucket map.
            it.object_name
                .as_deref()
                .and_then(|n| names.object_name_to_binding.get(n))
                .map(|b| match b {
                    ObjectBinding::Plain(_) => TermCoercion::None,
                    ObjectBinding::IdTyped(_) => TermCoercion::Id,
                    ObjectBinding::Typed { .. } => {
                        TermCoercion::Datatype(b.typed_datatype().unwrap())
                    }
                })
                .unwrap_or(TermCoercion::None)
        };

        by_key
            .entry(key)
            .or_insert_with(|| Bucket { items: Vec::new(), coercion })
            .items
            .push(it);
    }

    for (key, bucket) in by_key {
        let is_type = key == "@type";
        let values: Vec<Value> = bucket.items.iter()
            .map(|it| {
                if is_type {
                    type_to_json(it, prefixes)
                } else {
                    term_to_json(&it.object, grouped, prefixes, names, type_only, bucket.coercion)
                }
            })
            .collect();

        let value = match values.len() {
            1 => values.into_iter().next().unwrap(),
            _ => Value::Array(values),
        };
        obj.insert(key, value);
    }
}

/// Convert an `RdfTerm` to a JSON-LD value.
///
/// `coercion` reflects the surrounding predicate's `@context` binding and
/// lets us strip per-value `@id`/`@type` wrappers when the context will
/// re-attach the type information:
///   * `TermCoercion::Id` — `Uri` / `Curie` become bare strings.
///   * `TermCoercion::Datatype(dt)` — a `LiteralDatatype` whose datatype
///     matches `dt` becomes a bare string (the rest stay explicit, in case
///     the model and runtime data disagree about the type).
///   * `TermCoercion::None` — everything is emitted explicitly.
///
/// Other term types (blank nodes, simple literals, lang strings, numbers,
/// booleans) ignore the coercion and emit their natural JSON form.
fn term_to_json(
    term: &RdfTerm,
    grouped: &IndexMap<String, Vec<TripleItem>>,
    prefixes: &PrefixMap,
    names: &NameMaps,
    type_only: &HashSet<&str>,
    coercion: TermCoercion<'_>,
) -> Value {
    let id_typed = matches!(coercion, TermCoercion::Id);
    match term {
        RdfTerm::Uri(uri) => {
            let s = compact_iri(uri, prefixes);
            if id_typed {
                Value::String(s)
            } else {
                let mut m = Map::new();
                m.insert(ID_ALIAS.to_string(), Value::String(s));
                Value::Object(m)
            }
        }
        RdfTerm::Curie(curie) => {
            let s = compact_iri(curie, prefixes);
            if id_typed {
                Value::String(s)
            } else {
                let mut m = Map::new();
                m.insert(ID_ALIAS.to_string(), Value::String(s));
                Value::Object(m)
            }
        }
        RdfTerm::BlankNode(id) => build_blank_node(id, grouped, prefixes, names, type_only),
        RdfTerm::LiteralString(s) => Value::String(s.clone()),
        RdfTerm::LiteralInteger(i) => Value::Number((*i).into()),
        // Emit as a bare JSON number. This deliberately drops the explicit
        // xsd:decimal datatype — JSON-LD's native coercion for a JSON number
        // with a decimal point or exponent is xsd:double — in favor of the
        // shorter, far more readable form. Values that don't round-trip
        // cleanly through f64 (NaN, ±Infinity, malformed lexical forms)
        // fall back to a string so the writer stays total.
        RdfTerm::LiteralFloat(s) => s
            .parse::<f64>()
            .ok()
            .and_then(serde_json::Number::from_f64)
            .map(Value::Number)
            .unwrap_or_else(|| Value::String(s.clone())),
        RdfTerm::LiteralBoolean(b) => Value::Bool(*b),
        RdfTerm::LiteralLangString(s, lang) => {
            json!({ "@value": s, "@language": lang })
        }
        RdfTerm::LiteralDatatype(s, dt) => {
            // When the context-level binding declares the same datatype this
            // value carries, the wrapper is redundant — emit a bare string.
            // When they differ (or there's no binding), keep the explicit
            // `{"@value": ..., "@type": ...}` form so the type isn't lost.
            if let TermCoercion::Datatype(bound) = coercion {
                if bound == dt {
                    return Value::String(s.clone());
                }
            }
            json!({ "@value": s, "@type": compact_iri(dt, prefixes) })
        }
    }
}

/// Format the value of an `@type` key as a compact IRI / CURIE.
///
/// We no longer substitute the friendly subject name here: each subject name
/// is reserved as an `@id` alias in `@context`, so reusing it as a class IRI
/// in `@type` would conflict with that binding. The IRI form keeps `@type`
/// semantically unambiguous for JSON-LD consumers.
fn type_to_json(it: &TripleItem, prefixes: &PrefixMap) -> Value {
    match &it.object {
        RdfTerm::Uri(uri) => Value::String(compact_iri(uri, prefixes)),
        RdfTerm::Curie(curie) => Value::String(compact_iri(curie, prefixes)),
        other => Value::String(stringify_fallback(other, prefixes)),
    }
}

fn stringify_fallback(term: &RdfTerm, prefixes: &PrefixMap) -> String {
    match term {
        RdfTerm::Uri(uri) => compact_iri(uri, prefixes),
        RdfTerm::Curie(c) => compact_iri(c, prefixes),
        RdfTerm::BlankNode(id) => id.clone(),
        RdfTerm::LiteralString(s) => s.clone(),
        RdfTerm::LiteralInteger(i) => i.to_string(),
        RdfTerm::LiteralFloat(s) => s.clone(),
        RdfTerm::LiteralBoolean(b) => b.to_string(),
        RdfTerm::LiteralLangString(s, _) => s.clone(),
        RdfTerm::LiteralDatatype(s, _) => s.clone(),
    }
}

// ─── key/IRI formatting ────────────────────────────────────────────

/// Format a predicate as a JSON-LD object key (compact IRI when possible).
/// Used only as a fallback when no `object_name` is available on the triple.
fn format_predicate_key(predicate: &str, prefixes: &PrefixMap) -> String {
    if let Some((prefix, _)) = predicate.split_once(':') {
        if prefixes.contains_key(prefix) && !predicate.starts_with("http") {
            return predicate.to_string();
        }
    }
    compact_iri(predicate, prefixes)
}

/// Compact a full IRI into a CURIE using the longest matching prefix,
/// returning the original string when no prefix matches.
fn compact_iri(iri: &str, prefixes: &PrefixMap) -> String {
    if let Some((prefix, _)) = iri.split_once(':') {
        if prefixes.contains_key(prefix) && !iri.starts_with("http") {
            return iri.to_string();
        }
    }

    let mut prefix_vec: Vec<(&String, &String)> = prefixes.iter().collect();
    prefix_vec.sort_by(|a, b| b.1.len().cmp(&a.1.len()));

    for (prefix, base_uri) in &prefix_vec {
        if iri.starts_with(base_uri.as_str()) {
            let local = &iri[base_uri.len()..];
            if is_valid_compact_local(local) {
                return format!("{}:{}", prefix, local);
            }
        }
    }

    iri.to_string()
}

/// Whether `s` is usable as the local part of a JSON-LD compact IRI
/// (`prefix:s`). A JSON-LD compact IRI expands by plain string concatenation,
/// so the local part may legally contain characters — notably `#` — that a
/// Turtle `PN_LOCAL` would have to escape. `#` is allowed here so a fragment
/// IRI such as `http://identifiers.org/hco/1#GRCh37` compacts to the much
/// shorter `hco:1#GRCh37` (with prefix `hco` = `http://identifiers.org/hco/`)
/// instead of being left as a full IRI.
fn is_valid_compact_local(s: &str) -> bool {
    if s.is_empty() {
        return true;
    }
    s.chars().all(|c| {
        c.is_alphanumeric()
            || c == '_' || c == '-' || c == '.' || c == '/' || c == ':' || c == '#'
    })
}

// ─── helpers ───────────────────────────────────────────────────────

/// A predicate–object pair plus the model.yaml annotations attached to it.
/// Built from `Triple` during `group_triples` so the downstream code can
/// access the names without re-scanning the original triple list.
#[derive(Debug, Clone)]
struct TripleItem {
    predicate: String,
    object: RdfTerm,
    subject_name: Option<String>,
    object_name: Option<String>,
}

fn is_type_only_ref(obj: &RdfTerm, type_only: &HashSet<&str>) -> bool {
    match obj {
        RdfTerm::Uri(uri) => type_only.contains(uri.as_str()),
        RdfTerm::Curie(c) => type_only.contains(c.as_str()),
        _ => false,
    }
}

fn group_triples(triples: &[Triple]) -> IndexMap<String, Vec<TripleItem>> {
    let mut grouped: IndexMap<String, Vec<TripleItem>> = IndexMap::new();
    for triple in triples {
        grouped.entry(triple.subject.clone())
            .or_default()
            .push(TripleItem {
                predicate: triple.predicate.clone(),
                object: triple.object.clone(),
                subject_name: triple.subject_name.clone(),
                object_name: triple.object_name.clone(),
            });
    }
    grouped
}

/// Serialize a string as a JSON string literal (handles escaping).
fn json_string(s: &str) -> String {
    serde_json::to_string(s).unwrap_or_else(|_| format!("\"{}\"", s))
}

/// Write a JSON value pretty-printed, prefixing every line with `indent` spaces.
fn write_indented_value<W: Write>(writer: &mut W, value: &Value, indent: usize) -> std::io::Result<()> {
    let s = serde_json::to_string_pretty(value)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    let pad = " ".repeat(indent);
    let mut first = true;
    for line in s.lines() {
        if !first {
            writeln!(writer)?;
        }
        first = false;
        write!(writer, "{}{}", pad, line)?;
    }
    Ok(())
}
