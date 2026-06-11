use std::collections::HashSet;
use std::io::Write;
use indexmap::IndexMap;

use crate::types::*;

/// Write @prefix declarations (called once at the start)
pub fn write_prefixes<W: Write>(
    writer: &mut W,
    prefixes: &PrefixMap,
) -> std::io::Result<()> {
    for (prefix, uri) in prefixes {
        writeln!(writer, "@prefix {}: <{}> .", prefix, uri)?;
    }
    if !prefixes.is_empty() {
        writeln!(writer)?;
    }
    Ok(())
}

/// Write a chunk of triples as Turtle (without prefix declarations).
/// Filters out:
/// 1. Convert-generated subjects that only have rdf:type predicates
/// 2. Predicate-object pairs whose object references such a type-only subject
/// 3. Blank node subjects are inlined into their parent triples, recursively:
///    a blank node nested inside another blank node is expanded in place, so
///    arbitrarily deep `[]` chains become nested `[ ... [ ... ] ]` Turtle.
///
/// Auto-generated subjects (not in convert_subjects) are always kept.
///
/// Output is pretty-printed: predicates are indented one level under their
/// subject, and blank nodes open with `[` / close with `]` on their own
/// lines with their contents indented one level deeper, so nested `[]`
/// structures are visually obvious.
pub fn write_triples<W: Write>(
    writer: &mut W,
    triples: &[Triple],
    prefixes: &PrefixMap,
    first_subject: &mut bool,
    convert_subjects: &HashSet<String>,
) -> std::io::Result<()> {
    let grouped = group_triples(triples);

    // Identify type-only subjects among convert-generated subjects only
    let type_only: HashSet<&str> = grouped.iter()
        .filter(|(subj, pred_objs)| {
            convert_subjects.contains(subj.as_str()) &&
                pred_objs.iter().all(|(p, _)| p == "a" || p == "rdf:type")
        })
        .map(|(subj, _)| subj.as_str())
        .collect();

    // Identify blank node subjects (start with "_:")
    let bnode_subjects: HashSet<&str> = grouped.keys()
        .filter(|s| s.starts_with("_:"))
        .map(|s| s.as_str())
        .collect();

    // Write non-blank-node, non-type-only subjects
    for (subject, pred_objs) in &grouped {
        if type_only.contains(subject.as_str()) || bnode_subjects.contains(subject.as_str()) {
            continue;
        }

        let filtered_pred_objs: Vec<&(String, RdfTerm)> = pred_objs.iter()
            .filter(|(_, obj)| !is_type_only_ref(obj, &type_only))
            .collect();

        if filtered_pred_objs.is_empty() {
            continue;
        }

        if !*first_subject {
            writeln!(writer)?;
        }
        *first_subject = false;

        // Subject sits at indent level 0; its predicates at level 1.
        write!(writer, "{}", format_subject(subject, prefixes))?;

        let pred_groups = group_by_predicate_refs(&filtered_pred_objs);
        write_predicate_block(
            writer,
            pred_groups.iter().map(|(p, objs)| (*p, objs.as_slice())),
            pred_groups.len(),
            &grouped,
            prefixes,
            1,
            &mut HashSet::new(),
        )?;
        // Terminate the subject block.
        writeln!(writer, " .")?;
    }

    Ok(())
}

/// The number of spaces used per indentation level.
const INDENT: usize = 4;

/// Write `level` indentation levels worth of spaces.
fn write_indent<W: Write>(writer: &mut W, level: usize) -> std::io::Result<()> {
    for _ in 0..(level * INDENT) {
        write!(writer, " ")?;
    }
    Ok(())
}

/// Write a predicate-object block — the body shared by a top-level subject
/// and a blank node. Each predicate goes on its own line at `level`
/// indentation; multiple objects of one predicate are comma-separated, each
/// on its own line. Blank-node objects are expanded inline (and recursively)
/// via `write_inline_bnode` at `level + 1`.
///
/// The caller is responsible for writing whatever precedes this block (the
/// subject term, or the opening `[`) and whatever terminates it (` .` for a
/// subject, the closing `]` for a blank node). This function always begins
/// by emitting a newline, so the block's first predicate starts on a fresh
/// indented line.
fn write_predicate_block<'a, W, I>(
    writer: &mut W,
    pred_groups: I,
    num_preds: usize,
    grouped: &IndexMap<String, Vec<(String, RdfTerm)>>,
    prefixes: &PrefixMap,
    level: usize,
    visited: &mut HashSet<String>,
) -> std::io::Result<()>
where
    W: Write,
    I: Iterator<Item = (&'a str, &'a [&'a RdfTerm])>,
{
    for (pred_idx, (predicate, objects)) in pred_groups.enumerate() {
        // Each predicate starts on its own indented line.
        writeln!(writer)?;
        write_indent(writer, level)?;
        write!(writer, "{}", format_predicate(predicate, prefixes))?;

        for (obj_idx, object) in objects.iter().enumerate() {
            if obj_idx == 0 {
                write!(writer, " ")?;
            } else {
                // Subsequent objects of the same predicate: comma, newline,
                // then align at the predicate's own indent level. Using the
                // predicate level (rather than one deeper) keeps a blank
                // node object's opening `[` flush with its closing `]`,
                // which `write_inline_bnode` also emits at `level`.
                writeln!(writer, ",")?;
                write_indent(writer, level)?;
            }
            if let RdfTerm::BlankNode(bnode_id) = object {
                write_inline_bnode(writer, bnode_id, grouped, prefixes, level, visited)?;
            } else {
                write!(writer, "{}", format_object(object, prefixes))?;
            }
        }

        // Separate predicates with " ;"; the final predicate is left for the
        // caller to terminate (" ." or "]").
        if pred_idx < num_preds - 1 {
            write!(writer, " ;")?;
        }
    }
    Ok(())
}

/// Write a blank node inline as a pretty-printed `[ ... ]`.
///
/// The `[` opens on the current line; the blank node's predicates are
/// written one level deeper, each on its own line; the closing `]` sits on
/// its own line back at `level` indentation. Recurses when an object is
/// itself a blank node, so an arbitrarily deep chain of `[]` nodes (e.g.
/// CCLE's `faldo:location → [] → faldo:begin → [] → faldo:position → value`)
/// is emitted as readable, properly-indented nested Turtle rather than
/// leaving an inner `_:bN` id dangling.
///
/// `level` is the indentation level of the line that contains the opening
/// `[` (i.e. the predicate that points at this blank node). The blank node's
/// contents are therefore at `level + 1`.
///
/// `visited` holds the blank node ids currently being expanded on the path
/// from the top-level subject down to here. If a blank node's object refers
/// back to one of them the structure is cyclic and cannot be written as a
/// finite nested `[...]`; in that case the raw `_:bN` id is emitted instead,
/// which keeps the output valid Turtle (the other end of the cycle is still
/// reachable as its own subject) and guarantees termination.
fn write_inline_bnode<W: Write>(
    writer: &mut W,
    bnode_id: &str,
    grouped: &IndexMap<String, Vec<(String, RdfTerm)>>,
    prefixes: &PrefixMap,
    level: usize,
    visited: &mut HashSet<String>,
) -> std::io::Result<()> {
    // Cycle guard: if we're already expanding this blank node higher up the
    // stack, emit its id rather than recursing forever.
    if visited.contains(bnode_id) {
        write!(writer, "{}", bnode_id)?;
        return Ok(());
    }

    let Some(pred_objs) = grouped.get(bnode_id) else {
        // Blank node not found in this chunk — write as-is.
        write!(writer, "{}", bnode_id)?;
        return Ok(());
    };

    visited.insert(bnode_id.to_string());
    let pred_groups = group_by_predicate(pred_objs);

    if pred_groups.is_empty() {
        // Empty blank node — keep it compact.
        write!(writer, "[]")?;
    } else {
        // Open the blank node; contents are indented one level deeper than
        // the line carrying the `[`.
        write!(writer, "[")?;
        write_predicate_block(
            writer,
            pred_groups.iter().map(|(p, objs)| (*p, objs.as_slice())),
            pred_groups.len(),
            grouped,
            prefixes,
            level + 1,
            visited,
        )?;
        // Closing `]` on its own line, back at the opening line's level.
        writeln!(writer)?;
        write_indent(writer, level)?;
        write!(writer, "]")?;
    }

    visited.remove(bnode_id);
    Ok(())
}

/// Check if an object references a type-only subject
fn is_type_only_ref(obj: &RdfTerm, type_only: &HashSet<&str>) -> bool {
    match obj {
        RdfTerm::Uri(uri) => type_only.contains(uri.as_str()),
        RdfTerm::Curie(c) => type_only.contains(c.as_str()),
        _ => false,
    }
}

/// Group by predicate from a slice of references (used after filtering)
fn group_by_predicate_refs<'a>(pred_objs: &[&'a (String, RdfTerm)]) -> IndexMap<&'a str, Vec<&'a RdfTerm>> {
    let mut grouped: IndexMap<&'a str, Vec<&'a RdfTerm>> = IndexMap::new();
    for (pred, obj) in pred_objs.iter().copied() {
        grouped.entry(pred.as_str())
            .or_default()
            .push(obj);
    }
    grouped
}

/// Group triples by subject, preserving order
fn group_triples(triples: &[Triple]) -> IndexMap<String, Vec<(String, RdfTerm)>> {
    let mut grouped: IndexMap<String, Vec<(String, RdfTerm)>> = IndexMap::new();
    for triple in triples {
        grouped.entry(triple.subject.clone())
            .or_default()
            .push((triple.predicate.clone(), triple.object.clone()));
    }
    grouped
}

/// Group predicate-object pairs by predicate, preserving order.
/// Returns borrowed keys and values so the result type matches
/// `group_by_predicate_refs`, letting both feed `write_predicate_block`.
fn group_by_predicate<'a>(pred_objs: &'a [(String, RdfTerm)]) -> IndexMap<&'a str, Vec<&'a RdfTerm>> {
    let mut grouped: IndexMap<&'a str, Vec<&'a RdfTerm>> = IndexMap::new();
    for (pred, obj) in pred_objs {
        grouped.entry(pred.as_str())
            .or_default()
            .push(obj);
    }
    grouped
}

/// Format a subject for Turtle output
fn format_subject(subject: &str, prefixes: &PrefixMap) -> String {
    format_uri_or_curie(subject, prefixes)
}

/// Format a predicate for Turtle output
fn format_predicate(predicate: &str, prefixes: &PrefixMap) -> String {
    if predicate == "a" {
        return "a".to_string();
    }
    if let Some((prefix, _)) = predicate.split_once(':') {
        if prefixes.contains_key(prefix) {
            return predicate.to_string();
        }
    }
    format_uri_or_curie(predicate, prefixes)
}

/// Format an object for Turtle output
fn format_object(object: &RdfTerm, prefixes: &PrefixMap) -> String {
    match object {
        RdfTerm::Uri(uri) => format_uri_or_curie(uri, prefixes),
        RdfTerm::Curie(curie) => curie.clone(),
        RdfTerm::BlankNode(id) => id.clone(),
        RdfTerm::LiteralString(s) => format!("\"{}\"", escape_string(s)),
        RdfTerm::LiteralInteger(i) => i.to_string(),
        RdfTerm::LiteralFloat(s) => s.clone(),
        RdfTerm::LiteralBoolean(b) => if *b { "true".to_string() } else { "false".to_string() },
        RdfTerm::LiteralLangString(s, lang) => format!("\"{}\"@{}", escape_string(s), lang),
        RdfTerm::LiteralDatatype(s, dt) => format!("\"{}\"^^{}", escape_string(s), dt),
    }
}

/// Format a URI, compressing to CURIE if possible
fn format_uri_or_curie(uri: &str, prefixes: &PrefixMap) -> String {
    if let Some((prefix, _local)) = uri.split_once(':') {
        if prefixes.contains_key(prefix) && !uri.starts_with("http") {
            return uri.to_string();
        }
    }

    let mut prefix_vec: Vec<(&String, &String)> = prefixes.iter().collect();
    prefix_vec.sort_by(|a, b| b.1.len().cmp(&a.1.len()));

    for (prefix, base_uri) in &prefix_vec {
        if uri.starts_with(base_uri.as_str()) {
            let local = &uri[base_uri.len()..];
            if is_valid_local_name(local) {
                return format!("{}:{}", prefix, escape_pn_local(local));
            }
        }
    }

    format!("<{}>", uri)
}

fn is_valid_local_name(s: &str) -> bool {
    if s.is_empty() {
        return true;
    }
    s.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-' || c == '.' || c == '/' || c == ':')
}

/// Escape characters in a CURIE local name (PN_LOCAL) per Turtle grammar.
/// Characters such as '/' must be backslash-escaped: e.g. "pubmed/123" -> "pubmed\/123".
fn escape_pn_local(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '~' | '.' | '!' | '$' | '&' | '\'' | '(' | ')' | '*'
            | '+' | ',' | ';' | '=' | '/' | '?' | '#' | '@' | '%' => {
                out.push('\\');
                out.push(c);
            }
            _ => out.push(c),
        }
    }
    out
}

fn escape_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}
