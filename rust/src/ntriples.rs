use std::collections::HashSet;
use std::io::Write;

use crate::turtle_oxrdf::{filter_type_only_subjects, resolve_to_iri};
use crate::types::*;

/// XSD datatype IRIs used for typed literals that Turtle would otherwise
/// write in abbreviated bare form (`123`, `1.5`, `true`). N-Triples has no
/// such shorthand: every literal except a plain or language-tagged string
/// must carry an explicit `^^<datatype>`.
const XSD_INTEGER: &str = "http://www.w3.org/2001/XMLSchema#integer";
const XSD_DECIMAL: &str = "http://www.w3.org/2001/XMLSchema#decimal";
const XSD_DOUBLE: &str = "http://www.w3.org/2001/XMLSchema#double";
const XSD_BOOLEAN: &str = "http://www.w3.org/2001/XMLSchema#boolean";

/// The `rdf:type` IRI, written out in full because N-Triples has no `a`
/// keyword and no prefix mechanism.
const RDF_TYPE: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";

/// Write a chunk of triples in N-Triples format.
///
/// N-Triples is a deliberately minimal, line-based RDF serialization: every
/// triple is a self-contained line
///
/// ```text
/// <subject> <predicate> <object> .
/// ```
///
/// Compared with Turtle there are no `@prefix` declarations, no CURIE
/// abbreviation (every IRI is written out in full `<...>` form), no grouping
/// of triples by subject, and no blank-node nesting — a blank node is always
/// referenced by its bare `_:label` and emitted as the subject of its own
/// lines. Because each line stands alone there is also no document prelude
/// or postlude, so unlike Turtle and JSON-LD this serializer needs no
/// `first_subject` bookkeeping: chunks can simply be concatenated.
///
/// Filtering matches Turtle's: convert-generated subjects that carry nothing
/// but `rdf:type`, and predicate-object pairs that reference such subjects,
/// are dropped via [`filter_type_only_subjects`]. That function is
/// idempotent, so running it here is harmless even when the oxrdf validation
/// pass in `flush_chunk` has already filtered the same chunk.
pub fn write_triples<W: Write>(
    writer: &mut W,
    triples: &[Triple],
    prefixes: &PrefixMap,
    convert_subjects: &HashSet<String>,
) -> std::io::Result<()> {
    let filtered = filter_type_only_subjects(triples, convert_subjects);

    for triple in &filtered {
        let subject = format_subject(&triple.subject, prefixes);
        let predicate = format_predicate(&triple.predicate, prefixes);
        let object = format_object(&triple.object, prefixes);
        writeln!(writer, "{} {} {} .", subject, predicate, object)?;
    }

    Ok(())
}

/// Format a subject: a blank node (`_:label`) is emitted verbatim, anything
/// else is resolved to a full IRI and wrapped in `<...>`.
fn format_subject(subject: &str, prefixes: &PrefixMap) -> String {
    if let Some(label) = subject.strip_prefix("_:") {
        format_bnode(label)
    } else {
        format_iri(&resolve_to_iri(subject, prefixes))
    }
}

/// Format a predicate. The Turtle `a` shorthand expands to the full
/// `rdf:type` IRI; every other predicate is resolved to a full IRI.
fn format_predicate(predicate: &str, prefixes: &PrefixMap) -> String {
    if predicate == "a" {
        return format_iri(RDF_TYPE);
    }
    format_iri(&resolve_to_iri(predicate, prefixes))
}

/// Format an object term for N-Triples output.
fn format_object(object: &RdfTerm, prefixes: &PrefixMap) -> String {
    match object {
        RdfTerm::Uri(uri) => format_iri(&resolve_to_iri(uri, prefixes)),
        RdfTerm::Curie(curie) => format_iri(&resolve_to_iri(curie, prefixes)),
        RdfTerm::BlankNode(id) => {
            // Internal blank node ids carry a leading "_:"; strip it so
            // format_bnode receives just the label.
            format_bnode(id.strip_prefix("_:").unwrap_or(id))
        }
        RdfTerm::LiteralString(s) => format!("\"{}\"", escape_literal(s)),
        RdfTerm::LiteralInteger(i) => typed_literal(&i.to_string(), XSD_INTEGER),
        RdfTerm::LiteralFloat(s) => typed_literal(s, float_datatype(s)),
        RdfTerm::LiteralBoolean(b) => {
            typed_literal(if *b { "true" } else { "false" }, XSD_BOOLEAN)
        }
        RdfTerm::LiteralLangString(s, lang) => {
            format!("\"{}\"@{}", escape_literal(s), lang)
        }
        RdfTerm::LiteralDatatype(s, dt) => {
            typed_literal(s, &resolve_to_iri(dt, prefixes))
        }
    }
}

/// Build a `"value"^^<datatype>` typed literal.
fn typed_literal(value: &str, datatype_iri: &str) -> String {
    format!("\"{}\"^^{}", escape_literal(value), format_iri(datatype_iri))
}

/// Pick the XSD datatype for a `LiteralFloat` lexical value.
///
/// `xsd:decimal`'s lexical space is digits with an optional sign and decimal
/// point only — it does **not** permit an exponent. A value such as
/// `2.02145032467015E-5` therefore cannot be a `xsd:decimal` literal (it would
/// be ill-typed); the exponent form belongs to `xsd:double`. So any value
/// carrying an `e`/`E` exponent is typed `xsd:double`, and everything else
/// (plain `1.5`, `2.0`, `-0.003`) stays `xsd:decimal`. This matches how Turtle
/// interprets the same bare numeric tokens.
fn float_datatype(s: &str) -> &'static str {
    if s.contains('e') || s.contains('E') {
        XSD_DOUBLE
    } else {
        XSD_DECIMAL
    }
}

/// Format a blank node label as `_:label`.
fn format_bnode(label: &str) -> String {
    format!("_:{}", label)
}

/// Wrap a full IRI in angle brackets, escaping the characters the N-Triples
/// `IRIREF` grammar forbids (control characters `U+0000`–`U+0020` and the
/// delimiters `<` `>` `"` `{` `}` `|` `^` `` ` `` `\`) as `\uXXXX`. Other
/// characters, including non-ASCII ones, are passed through unchanged: RDF
/// 1.1 N-Triples is a UTF-8 format.
fn format_iri(iri: &str) -> String {
    let mut out = String::with_capacity(iri.len() + 2);
    out.push('<');
    for c in iri.chars() {
        match c {
            '\u{00}'..='\u{20}' | '<' | '>' | '"' | '{' | '}' | '|' | '^' | '`' | '\\' => {
                out.push_str(&format!("\\u{:04X}", c as u32));
            }
            _ => out.push(c),
        }
    }
    out.push('>');
    out
}

/// Escape a string for use inside an N-Triples quoted literal. The common
/// control characters get their short `ECHAR` escapes; any remaining control
/// character below `U+0020` falls back to a `\uXXXX` escape. Non-ASCII
/// characters are emitted as-is (N-Triples is UTF-8).
fn escape_literal(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0C}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out
}
