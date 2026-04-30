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

    // Post-processing: fix reference detection using known subject names
    let subject_names: Vec<String> = subjects.iter().map(|s| s.name.clone()).collect();
    for subject in &mut subjects {
        for predicate in &mut subject.predicates {
            for object in &mut predicate.objects {
                fix_reference_type(object, &subject_names);
            }
            for bng in &mut predicate.blank_node_groups {
                for object in &mut bng.objects {
                    fix_reference_type(object, &subject_names);
                }
            }
        }
    }

    Ok(Model { subjects })
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

    let predicates_array = value.as_sequence()
        .with_context(|| format!("Subject '{}' value must be a sequence", name))?;

    let mut rdf_types = Vec::new();
    let mut predicates = Vec::new();

    for pred_item in predicates_array {
        let pred_mapping = pred_item.as_mapping()
            .with_context(|| format!("Predicate item in '{}' must be a mapping", name))?;

        for (pred_key, pred_value) in pred_mapping {
            let pred_str = yaml_key_to_string(pred_key);
            let (pred_uri, _) = parse_predicate_with_cardinality(&pred_str);

            if pred_uri == "a" || pred_uri == "rdf:type" {
                parse_rdf_types(pred_value, &mut rdf_types);
            } else {
                let (objects, blank_node_groups) = parse_objects_and_bnodes(pred_value, prefixes)?;
                let (clean_pred, cardinality) = parse_predicate_with_cardinality(&pred_str);
                predicates.push(PredicateDef {
                    uri: clean_pred.to_string(),
                    cardinality,
                    objects,
                    blank_node_groups,
                });
            }
        }
    }

    Ok(SubjectDef {
        name,
        example_uris,
        rdf_types,
        predicates,
    })
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

fn parse_objects(value: &Value, prefixes: &PrefixMap) -> Result<Vec<ObjectDef>> {
    let (objects, _) = parse_objects_and_bnodes(value, prefixes)?;
    Ok(objects)
}

/// Parse objects and blank node groups from a predicate value.
/// Returns (regular_objects, blank_node_groups).
fn parse_objects_and_bnodes(value: &Value, prefixes: &PrefixMap) -> Result<(Vec<ObjectDef>, Vec<BlankNodeGroupDef>)> {
    let mut objects = Vec::new();
    let mut blank_node_groups = Vec::new();

    match value {
        Value::Mapping(mapping) => {
            for (k, v) in mapping {
                if is_empty_sequence(k) {
                    parse_blank_node_group(v, prefixes, &mut blank_node_groups)?;
                } else {
                    let obj = parse_single_object(&yaml_key_to_string(k), v, prefixes)?;
                    objects.push(obj);
                }
            }
        }
        Value::Sequence(seq) => {
            for item in seq {
                if let Value::Mapping(mapping) = item {
                    for (k, v) in mapping {
                        if is_empty_sequence(k) {
                            parse_blank_node_group(v, prefixes, &mut blank_node_groups)?;
                        } else {
                            let obj = parse_single_object(&yaml_key_to_string(k), v, prefixes)?;
                            objects.push(obj);
                        }
                    }
                }
            }
        }
        Value::String(s) => {
            objects.push(ObjectDef {
                name: String::new(),
                value_type: determine_value_type(s, prefixes),
                example_values: vec![s.clone()],
            });
        }
        _ => {}
    }

    Ok((objects, blank_node_groups))
}

/// Check if a YAML value is an empty sequence (represents `[]` blank node marker)
fn is_empty_sequence(v: &Value) -> bool {
    matches!(v, Value::Sequence(seq) if seq.is_empty())
}

/// Parse a blank node group: `[] → { inner_predicate → [object1, object2, ...] }`
fn parse_blank_node_group(value: &Value, prefixes: &PrefixMap, groups: &mut Vec<BlankNodeGroupDef>) -> Result<()> {
    let items = match value {
        Value::Sequence(seq) => seq,
        Value::Mapping(mapping) => {
            // Direct mapping under []
            for (k, v) in mapping {
                let inner_pred = yaml_key_to_string(k);
                let inner_objects = parse_objects(v, prefixes)?;
                groups.push(BlankNodeGroupDef {
                    inner_predicate: inner_pred,
                    objects: inner_objects,
                });
            }
            return Ok(());
        }
        _ => return Ok(()),
    };

    for item in items {
        if let Value::Mapping(mapping) = item {
            for (k, v) in mapping {
                let inner_pred = yaml_key_to_string(k);
                let inner_objects = parse_objects(v, prefixes)?;
                groups.push(BlankNodeGroupDef {
                    inner_predicate: inner_pred,
                    objects: inner_objects,
                });
            }
        }
    }
    Ok(())
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

impl Model {
    pub fn find_subject(&self, name: &str) -> Option<&SubjectDef> {
        self.subjects.iter().find(|s| s.name == name)
    }

    pub fn find_object(&self, obj_name: &str) -> Option<(&SubjectDef, &PredicateDef, &ObjectDef)> {
        for subject in &self.subjects {
            for predicate in &subject.predicates {
                for object in &predicate.objects {
                    if object.name == obj_name {
                        return Some((subject, predicate, object));
                    }
                }
                for bng in &predicate.blank_node_groups {
                    for object in &bng.objects {
                        if object.name == obj_name {
                            return Some((subject, predicate, object));
                        }
                    }
                }
            }
        }
        None
    }

    pub fn find_predicate_for_object(&self, subject_name: &str, obj_name: &str) -> Option<&PredicateDef> {
        if let Some(subject) = self.find_subject(subject_name) {
            for predicate in &subject.predicates {
                for object in &predicate.objects {
                    if object.name == obj_name {
                        return Some(predicate);
                    }
                }
                for bng in &predicate.blank_node_groups {
                    for object in &bng.objects {
                        if object.name == obj_name {
                            return Some(predicate);
                        }
                    }
                }
            }
        }
        None
    }

    pub fn find_object_in_subject(&self, subject_name: &str, obj_name: &str) -> Option<&ObjectDef> {
        if let Some(subject) = self.find_subject(subject_name) {
            for predicate in &subject.predicates {
                for object in &predicate.objects {
                    if object.name == obj_name {
                        return Some(object);
                    }
                }
                for bng in &predicate.blank_node_groups {
                    for object in &bng.objects {
                        if object.name == obj_name {
                            return Some(object);
                        }
                    }
                }
            }
        }
        None
    }

    /// Find which blank node group an object name belongs to, if any.
    /// Returns (outer_predicate_uri, inner_predicate_uri, group_index_within_pred).
    pub fn find_blank_node_group_for_object(&self, subject_name: &str, obj_name: &str)
        -> Option<(&str, &BlankNodeGroupDef)>
    {
        if let Some(subject) = self.find_subject(subject_name) {
            for predicate in &subject.predicates {
                for bng in &predicate.blank_node_groups {
                    if bng.objects.iter().any(|o| o.name == obj_name) {
                        return Some((&predicate.uri, bng));
                    }
                }
            }
        }
        None
    }

    pub fn subject_names(&self) -> Vec<&str> {
        self.subjects.iter().map(|s| s.name.as_str()).collect()
    }
}
