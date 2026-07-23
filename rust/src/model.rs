use anyhow::{Context, Result};
use serde_yaml::Value;
use std::path::Path;

use crate::prefix::{is_uri_like, is_known_curie};
use crate::types::*;

/// Parse model.yaml
pub fn parse_model_yaml(path: &Path, prefixes: &PrefixMap) -> Result<Model> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read model.yaml: {}", path.display()))?;
    let yaml: Value = serde_yaml::from_str(&content)
        .with_context(|| "Failed to parse model.yaml")?;

    let top_array = yaml.as_sequence()
        .with_context(|| "model.yaml top level must be a sequence")?;

    let mut subjects = Vec::new();

    for item in top_array {
        let mapping = item.as_mapping()
            .with_context(|| "Each top-level item in model.yaml must be a mapping")?;

        for (key, value) in mapping {
            let subject_line = yaml_key_to_string(key);
            let subject_def = parse_subject_def(&subject_line, value, prefixes)?;
            subjects.push(subject_def);
        }
    }

    // Post-processing: fix reference detection using known subject names.
    // Recurses through nested blank nodes so deeply-nested leaf objects get
    // the same treatment as top-level ones.
    let subject_names: Vec<String> = subjects.iter().map(|s| s.name.clone()).collect();
    for subject in &mut subjects {
        fix_reference_types_in_predicates(&mut subject.predicates, &subject_names);
    }

    Ok(Model { subjects })
}

/// Recursively apply `fix_reference_type` to every leaf object reachable
/// from a list of predicates, descending into nested blank nodes.
fn fix_reference_types_in_predicates(predicates: &mut [PredicateDef], subject_names: &[String]) {
    for predicate in predicates {
        for child in &mut predicate.children {
            match child {
                ObjectSpec::Leaf(obj) => fix_reference_type(obj, subject_names),
                ObjectSpec::Blank(bnode) => {
                    fix_reference_types_in_predicates(&mut bnode.predicates, subject_names);
                }
            }
        }
    }
}

/// Fix object value types: only classify as Reference if value matches a known subject name
fn fix_reference_type(obj: &mut ObjectDef, subject_names: &[String]) {
    match &obj.value_type {
        ObjectValueType::Reference(ref_name) => {
            if !subject_names.contains(ref_name) {
                // Not a known subject -> treat as string literal
                obj.value_type = ObjectValueType::LiteralString;
            }
        }
        ObjectValueType::ReferenceList(refs) => {
            let valid_refs: Vec<String> = refs.iter()
                .filter(|r| subject_names.contains(r))
                .cloned()
                .collect();
            if valid_refs.is_empty() {
                obj.value_type = ObjectValueType::LiteralString;
            } else if valid_refs.len() != refs.len() {
                obj.value_type = ObjectValueType::ReferenceList(valid_refs);
            }
        }
        _ => {}
    }
}

fn parse_subject_def(subject_line: &str, value: &Value, prefixes: &PrefixMap) -> Result<SubjectDef> {
    let parts: Vec<&str> = subject_line.split_whitespace().collect();
    let name = parts[0].to_string();
    let example_uris: Vec<String> = parts[1..].iter().map(|s| s.to_string()).collect();

    // A subject's body has the same shape as a blank node's body: a list of
    // predicate entries, with `a:` / `rdf:type:` collected as rdf_types.
    let (rdf_types, predicates) = parse_node_body(value, prefixes)
        .with_context(|| format!("Failed to parse subject '{}'", name))?;

    Ok(SubjectDef {
        name,
        example_uris,
        rdf_types,
        predicates,
    })
}

/// Parse a "node body" — the value under a subject or under a `[]` blank node.
///
/// The body is a sequence (or mapping) of single-entry predicate mappings.
/// Each entry's key is a predicate (or `a` / `rdf:type`); `a` entries are
/// collected into `rdf_types`, everything else becomes a `PredicateDef`.
/// Mutually recursive with `parse_predicate_children`.
fn parse_node_body(value: &Value, prefixes: &PrefixMap) -> Result<(Vec<String>, Vec<PredicateDef>)> {
    let mut rdf_types = Vec::new();
    let mut predicates = Vec::new();

    // Collect (key, value) predicate entries from either a sequence of
    // single-entry mappings or a direct mapping.
    let handle_entry = |k: &Value, v: &Value, rdf_types: &mut Vec<String>, predicates: &mut Vec<PredicateDef>| -> Result<()> {
        let pred_str = yaml_key_to_string(k);
        let (pred_uri, cardinality) = parse_predicate_with_cardinality(&pred_str);
        if pred_uri == "a" || pred_uri == "rdf:type" {
            parse_rdf_types(v, rdf_types);
        } else {
            let children = parse_predicate_children(v, prefixes)?;
            predicates.push(PredicateDef {
                uri: pred_uri.to_string(),
                cardinality,
                children,
            });
        }
        Ok(())
    };

    match value {
        Value::Sequence(seq) => {
            for item in seq {
                if let Value::Mapping(mapping) = item {
                    for (k, v) in mapping {
                        handle_entry(k, v, &mut rdf_types, &mut predicates)?;
                    }
                }
            }
        }
        Value::Mapping(mapping) => {
            for (k, v) in mapping {
                handle_entry(k, v, &mut rdf_types, &mut predicates)?;
            }
        }
        _ => {}
    }

    Ok((rdf_types, predicates))
}

/// Parse the value attached to a single predicate into its children.
///
/// The value is a sequence (or mapping) of single-entry mappings. Each
/// entry is either `[]: <body>` (a blank node — recurse via
/// `parse_node_body`) or `objName: value` (a named leaf object).
/// Mutually recursive with `parse_node_body`.
fn parse_predicate_children(value: &Value, prefixes: &PrefixMap) -> Result<Vec<ObjectSpec>> {
    let mut children = Vec::new();

    let handle_entry = |k: &Value, v: &Value, children: &mut Vec<ObjectSpec>| -> Result<()> {
        if is_empty_sequence(k) {
            // `[]` blank node: its value is another node body.
            let (rdf_types, predicates) = parse_node_body(v, prefixes)?;
            children.push(ObjectSpec::Blank(BlankNodeDef { rdf_types, predicates }));
        } else {
            let obj = parse_single_object(&yaml_key_to_string(k), v, prefixes)?;
            children.push(ObjectSpec::Leaf(obj));
        }
        Ok(())
    };

    match value {
        Value::Sequence(seq) => {
            for item in seq {
                if let Value::Mapping(mapping) = item {
                    for (k, v) in mapping {
                        handle_entry(k, v, &mut children)?;
                    }
                }
            }
        }
        Value::Mapping(mapping) => {
            for (k, v) in mapping {
                handle_entry(k, v, &mut children)?;
            }
        }
        Value::String(s) => {
            // A bare string directly under a predicate: an anonymous leaf.
            children.push(ObjectSpec::Leaf(ObjectDef {
                name: String::new(),
                value_type: determine_value_type(s, prefixes),
                example_values: vec![s.clone()],
            }));
        }
        _ => {}
    }

    Ok(children)
}

fn parse_rdf_types(value: &Value, types: &mut Vec<String>) {
    match value {
        Value::String(s) => {
            types.push(s.clone());
        }
        Value::Sequence(seq) => {
            for item in seq {
                if let Value::String(s) = item {
                    types.push(s.clone());
                }
            }
        }
        _ => {}
    }
}

/// Check if a YAML value is an empty sequence (represents `[]` blank node marker)
fn is_empty_sequence(v: &Value) -> bool {
    matches!(v, Value::Sequence(seq) if seq.is_empty())
}

fn parse_single_object(name: &str, value: &Value, prefixes: &PrefixMap) -> Result<ObjectDef> {
    match value {
        Value::Null => {
            Ok(ObjectDef {
                name: name.to_string(),
                value_type: ObjectValueType::LiteralString,
                example_values: vec![],
            })
        }
        Value::String(s) => {
            let value_type = determine_value_type(s, prefixes);
            Ok(ObjectDef {
                name: name.to_string(),
                value_type,
                example_values: vec![s.clone()],
            })
        }
        Value::Number(n) => {
            if n.is_i64() || n.is_u64() {
                let i = n.as_i64().unwrap_or(0);
                Ok(ObjectDef {
                    name: name.to_string(),
                    value_type: ObjectValueType::LiteralInteger,
                    example_values: vec![i.to_string()],
                })
            } else {
                let f = n.as_f64().unwrap_or(0.0);
                Ok(ObjectDef {
                    name: name.to_string(),
                    value_type: ObjectValueType::LiteralFloat,
                    example_values: vec![format!("{}", f)],
                })
            }
        }
        Value::Bool(b) => {
            Ok(ObjectDef {
                name: name.to_string(),
                value_type: ObjectValueType::LiteralBoolean,
                example_values: vec![b.to_string()],
            })
        }
        Value::Sequence(seq) => {
            let mut refs = Vec::new();
            let mut all_string_refs = true;
            for item in seq {
                if let Value::String(s) = item {
                    if is_potential_subject_ref(s) && !is_uri_like(s, prefixes) {
                        refs.push(s.clone());
                    } else {
                        all_string_refs = false;
                        break;
                    }
                } else {
                    all_string_refs = false;
                    break;
                }
            }
            if all_string_refs && !refs.is_empty() {
                Ok(ObjectDef {
                    name: name.to_string(),
                    value_type: ObjectValueType::ReferenceList(refs),
                    example_values: vec![],
                })
            } else {
                Ok(ObjectDef {
                    name: name.to_string(),
                    value_type: ObjectValueType::LiteralString,
                    example_values: vec![],
                })
            }
        }
        _ => {
            Ok(ObjectDef {
                name: name.to_string(),
                value_type: ObjectValueType::LiteralString,
                example_values: vec![],
            })
        }
    }
}

fn determine_value_type(s: &str, prefixes: &PrefixMap) -> ObjectValueType {
    let s = s.trim();

    // Language tag: '"value"@lang'
    if s.starts_with('"') && s.contains("\"@") {
        if let Some(at_pos) = s.rfind("\"@") {
            let lang = s[at_pos + 2..].trim_end_matches('\'').to_string();
            return ObjectValueType::LiteralLangString { lang };
        }
    }

    // Datatype: '"value"^^type'
    if s.starts_with('"') && s.contains("\"^^") {
        if let Some(hat_pos) = s.rfind("\"^^") {
            let dt = s[hat_pos + 3..].trim_end_matches('\'').to_string();
            return ObjectValueType::LiteralDatatype { datatype: dt };
        }
    }

    // URI in angle brackets
    if s.starts_with('<') && s.ends_with('>') {
        return ObjectValueType::Uri;
    }

    // Known CURIE
    if is_known_curie(s, prefixes) {
        return ObjectValueType::Uri;
    }

    // Potential subject reference (CamelCase) – will be validated in post-processing
    if is_potential_subject_ref(s) {
        return ObjectValueType::Reference(s.to_string());
    }

    ObjectValueType::LiteralString
}

/// Check if a string could be a subject name reference (CamelCase)
fn is_potential_subject_ref(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let first = s.chars().next().unwrap();
    first.is_uppercase()
        && !s.contains(':')
        && !s.contains('<')
        && !s.contains(' ')
        && !s.contains('"')
        && s.chars().all(|c| c.is_alphanumeric() || c == '_')
}

fn parse_predicate_with_cardinality(pred: &str) -> (&str, Cardinality) {
    let pred = pred.trim();

    if pred.ends_with('?') {
        (&pred[..pred.len() - 1], Cardinality::ZeroOrOne)
    } else if pred.ends_with('*') {
        (&pred[..pred.len() - 1], Cardinality::ZeroOrMore)
    } else if pred.ends_with('+') {
        (&pred[..pred.len() - 1], Cardinality::OneOrMore)
    } else if pred.ends_with('}') {
        if let Some(brace_start) = pred.rfind('{') {
            let inner = &pred[brace_start + 1..pred.len() - 1];
            let base = &pred[..brace_start];
            if let Some((n_str, m_str)) = inner.split_once(',') {
                let n = n_str.trim().parse().unwrap_or(0);
                let m = m_str.trim().parse().unwrap_or(0);
                (base, Cardinality::Range(n, m))
            } else {
                let n = inner.trim().parse().unwrap_or(1);
                (base, Cardinality::Exact(n))
            }
        } else {
            (pred, Cardinality::ExactlyOne)
        }
    } else {
        (pred, Cardinality::ExactlyOne)
    }
}

fn yaml_key_to_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        _ => format!("{:?}", value),
    }
}

// ─── model queries ────────────────────────────────────────────────

/// One blank node traversed on the way from a subject to a leaf object.
#[derive(Debug, Clone)]
pub struct BlankStep<'a> {
    /// Predicate leading from the parent (subject or outer blank node) into
    /// this blank node.
    pub predicate: &'a str,
    /// `rdf:type` values declared on this blank node (may be empty).
    pub rdf_types: &'a [String],
}

/// A resolved path from a subject down to a single named leaf object.
///
/// `blanks` lists the blank nodes traversed, outermost first; it is empty
/// when the leaf attaches directly to the subject. `leaf_predicate` is the
/// predicate attaching the leaf value to its immediate parent (the subject
/// when `blanks` is empty, otherwise the innermost blank node).
#[derive(Debug, Clone)]
pub struct ObjectPath<'a> {
    pub blanks: Vec<BlankStep<'a>>,
    pub leaf_predicate: &'a str,
    pub leaf: &'a ObjectDef,
}

/// Depth-first search for a named leaf object within a predicate list,
/// accumulating the blank-node path taken to reach it.
fn search_predicates<'a>(
    predicates: &'a [PredicateDef],
    obj_name: &str,
    blanks: &mut Vec<BlankStep<'a>>,
) -> Option<ObjectPath<'a>> {
    for predicate in predicates {
        for child in &predicate.children {
            match child {
                ObjectSpec::Leaf(obj) => {
                    if obj.name == obj_name {
                        return Some(ObjectPath {
                            blanks: blanks.clone(),
                            leaf_predicate: &predicate.uri,
                            leaf: obj,
                        });
                    }
                }
                ObjectSpec::Blank(bnode) => {
                    blanks.push(BlankStep {
                        predicate: &predicate.uri,
                        rdf_types: &bnode.rdf_types,
                    });
                    if let Some(found) = search_predicates(&bnode.predicates, obj_name, blanks) {
                        return Some(found);
                    }
                    blanks.pop();
                }
            }
        }
    }
    None
}

/// Recursively collect every named leaf object reachable from a predicate
/// list, each paired with the predicate that directly attaches it.
fn collect_leaves<'a>(predicates: &'a [PredicateDef], out: &mut Vec<(&'a ObjectDef, &'a str)>) {
    for predicate in predicates {
        for child in &predicate.children {
            match child {
                ObjectSpec::Leaf(obj) => out.push((obj, predicate.uri.as_str())),
                ObjectSpec::Blank(bnode) => collect_leaves(&bnode.predicates, out),
            }
        }
    }
}

impl SubjectDef {
    /// Every named leaf object anywhere under this subject (descending
    /// through nested blank nodes), paired with the predicate that directly
    /// attaches each leaf to its immediate parent.
    pub fn leaf_objects(&self) -> Vec<(&ObjectDef, &str)> {
        let mut out = Vec::new();
        collect_leaves(&self.predicates, &mut out);
        out
    }
}

impl Model {
    pub fn find_subject(&self, name: &str) -> Option<&SubjectDef> {
        self.subjects.iter().find(|s| s.name == name)
    }

    /// Resolve the path from a subject to one of its named leaf objects.
    ///
    /// Returns `None` when the subject is unknown or has no leaf object with
    /// the given name (at any depth). The returned `ObjectPath` carries the
    /// blank-node chain, the attaching predicate, and the `ObjectDef`.
    pub fn object_path<'a>(&'a self, subject_name: &str, obj_name: &str) -> Option<ObjectPath<'a>> {
        let subject = self.find_subject(subject_name)?;
        let mut blanks = Vec::new();
        search_predicates(&subject.predicates, obj_name, &mut blanks)
    }

    pub fn subject_names(&self) -> Vec<&str> {
        self.subjects.iter().map(|s| s.name.as_str()).collect()
    }
}
