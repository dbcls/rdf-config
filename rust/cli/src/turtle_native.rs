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
/// 3. Blank node subjects are inlined into their parent triples
///
/// Auto-generated subjects (not in convert_subjects) are always kept.
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

        write!(writer, "{}", format_subject(subject, prefixes))?;

        let pred_groups = group_by_predicate_refs(&filtered_pred_objs);

        let num_predicates = pred_groups.len();
        for (pred_idx, (predicate, objects)) in pred_groups.iter().enumerate() {
            if pred_idx == 0 {
                write!(writer, " ")?;
            } else {
                write!(writer, "  ")?;
            }

            write!(writer, "{}", format_predicate(predicate, prefixes))?;

            for (obj_idx, object) in objects.iter().enumerate() {
                if obj_idx == 0 {
                    write!(writer, " ")?;
                } else {
                    writeln!(writer, ",")?;
                    write!(writer, "    ")?;
                }
                // Check if object is a blank node reference → inline it
                if let RdfTerm::BlankNode(bnode_id) = object {
                    write_inline_bnode(writer, bnode_id, &grouped, prefixes)?;
                } else {
                    write!(writer, "{}", format_object(object, prefixes))?;
                }
            }

            if pred_idx < num_predicates - 1 {
                writeln!(writer, " ;")?;
            } else {
                writeln!(writer, " .")?;
            }
        }
    }

    Ok(())
}

/// Write a blank node inline as `[pred obj1, obj2]`
fn write_inline_bnode<W: Write>(
    writer: &mut W,
    bnode_id: &str,
    grouped: &IndexMap<String, Vec<(String, RdfTerm)>>,
    prefixes: &PrefixMap,
) -> std::io::Result<()> {
    if let Some(pred_objs) = grouped.get(bnode_id) {
        let pred_groups = group_by_predicate(pred_objs);
        write!(writer, "[")?;
        let num_preds = pred_groups.len();
        for (pi, (pred, objs)) in pred_groups.iter().enumerate() {
            write!(writer, "{}", format_predicate(pred, prefixes))?;
            for (oi, obj) in objs.iter().enumerate() {
                if oi == 0 {
                    write!(writer, " ")?;
                } else {
                    write!(writer, ",\n    ")?;
                }
                write!(writer, "{}", format_object(obj, prefixes))?;
            }
            if pi < num_preds - 1 {
                write!(writer, ";\n  ")?;
            }
        }
        write!(writer, "]")?;
    } else {
        // Blank node not found in this chunk — write as-is
        write!(writer, "{}", bnode_id)?;
    }
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

/// Group predicate-object pairs by predicate, preserving order
fn group_by_predicate(pred_objs: &[(String, RdfTerm)]) -> IndexMap<String, Vec<RdfTerm>> {
    let mut grouped: IndexMap<String, Vec<RdfTerm>> = IndexMap::new();
    for (pred, obj) in pred_objs {
        grouped.entry(pred.clone())
            .or_default()
            .push(obj.clone());
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
