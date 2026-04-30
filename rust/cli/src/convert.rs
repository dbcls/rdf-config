use anyhow::{Context, Result, bail};
use serde_yaml::Value;
use std::path::Path;

use crate::types::*;

/// Parse convert.yaml
pub fn parse_convert_yaml(path: &Path) -> Result<ConvertConfig> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read convert.yaml: {}", path.display()))?;
    let yaml: Value = serde_yaml::from_str(&content)
        .with_context(|| "Failed to parse convert.yaml")?;

    let top_array = yaml.as_sequence()
        .with_context(|| "convert.yaml top level must be a sequence")?;

    let mut subject_rules = Vec::new();

    for item in top_array {
        let mapping = item.as_mapping()
            .with_context(|| "Each top-level item in convert.yaml must be a mapping")?;

        for (key, value) in mapping {
            let name = yaml_value_to_string(key);
            let rule = parse_subject_rule(&name, value)?;
            subject_rules.push(rule);
        }
    }

    Ok(ConvertConfig { subject_rules })
}

fn parse_subject_rule(name: &str, value: &Value) -> Result<SubjectRule> {
    let items = value.as_sequence()
        .with_context(|| format!("Subject rule '{}' value must be a sequence", name))?;

    let mut source_path = None;
    let mut source_format = None;
    let mut pre_variables = Vec::new();
    let mut subject_pipeline = SubjectPipeline {
        variables: Vec::new(),
        steps: Vec::new(),
    };
    let mut object_rules = Vec::new();

    for item in items {
        match item {
            Value::String(s) => {
                // Top-level string: could be source() or a variable reference
                if let Some(src) = parse_source_call(s) {
                    source_path = Some(src.0);
                    source_format = src.1;
                } else if s.starts_with('$') {
                    // Variable reference at top level (unusual but possible)
                    pre_variables.push(VariableDef {
                        name: s.clone(),
                        pipeline: vec![Operation::VarRef(s.clone())],
                    });
                }
            }
            Value::Mapping(mapping) => {
                for (k, v) in mapping {
                    let key = yaml_value_to_string(k);

                    if key == "subject" {
                        subject_pipeline = parse_subject_pipeline(v)?;
                    } else if key == "objects" {
                        object_rules = parse_object_rules(v)?;
                    } else if key.starts_with('$') {
                        // Variable definition at top level
                        let pipeline = parse_pipeline_value(v)?;
                        pre_variables.push(VariableDef {
                            name: key,
                            pipeline,
                        });
                    } else {
                        // Could be source or other directive
                        // Check if it's a source-like thing
                    }
                }
            }
            _ => {}
        }
    }

    Ok(SubjectRule {
        name: name.to_string(),
        source_path,
        source_format,
        pre_variables,
        subject_pipeline,
        object_rules,
    })
}

fn parse_subject_pipeline(value: &Value) -> Result<SubjectPipeline> {
    let mut variables = Vec::new();
    let mut steps = Vec::new();

    match value {
        Value::Sequence(seq) => {
            for item in seq {
                match item {
                    Value::String(s) => {
                        // Pipeline step (function call or variable ref or string template)
                        let op = parse_operation(s)?;
                        steps.push(op);
                    }
                    Value::Mapping(mapping) => {
                        // Variable definition inside subject pipeline
                        for (k, v) in mapping {
                            let key = yaml_value_to_string(k);
                            if key.starts_with('$') {
                                let pipeline = parse_pipeline_value(v)?;
                                variables.push(VariableDef {
                                    name: key,
                                    pipeline,
                                });
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        Value::String(s) => {
            let op = parse_operation(s)?;
            steps.push(op);
        }
        _ => {}
    }

    Ok(SubjectPipeline { variables, steps })
}

fn parse_object_rules(value: &Value) -> Result<Vec<ObjectRule>> {
    let mut rules = Vec::new();

    let items = match value {
        Value::Sequence(seq) => seq,
        _ => return Ok(rules),
    };

    for item in items {
        if let Value::Mapping(mapping) = item {
            for (k, v) in mapping {
                let key = yaml_value_to_string(k);

                if key.starts_with('$') {
                    // Variable definition inside objects section
                    // This is handled as a special rule
                    let pipeline = parse_pipeline_value(v)?;
                    rules.push(ObjectRule {
                        name: key,
                        pipeline,
                    });
                } else {
                    let pipeline = parse_pipeline_value(v)?;
                    rules.push(ObjectRule {
                        name: key,
                        pipeline,
                    });
                }
            }
        }
    }

    Ok(rules)
}

fn parse_pipeline_value(value: &Value) -> Result<Vec<Operation>> {
    match value {
        Value::String(s) => {
            Ok(vec![parse_operation(s)?])
        }
        Value::Sequence(seq) => {
            let mut ops = Vec::new();
            for item in seq {
                match item {
                    Value::String(s) => {
                        ops.push(parse_operation(s)?);
                    }
                    Value::Mapping(mapping) => {
                        // Could be a variable definition or a switch within the pipeline
                        for (k, v) in mapping {
                            let key = yaml_value_to_string(k);
                            if key.starts_with('$') {
                                // Inline variable: store as VarDef operation
                                let sub_pipeline = parse_pipeline_value(v)?;
                                ops.push(Operation::InlineVarDef(key, sub_pipeline));
                            } else if key == "switch" || key.starts_with("switch(") {
                                ops.push(parse_switch_operation(&key, v)?);
                            }
                        }
                    }
                    Value::Number(n) => {
                        // Plain number as value
                        ops.push(Operation::StringTemplate(n.to_string()));
                    }
                    _ => {}
                }
            }
            Ok(ops)
        }
        Value::Number(n) => {
            Ok(vec![Operation::StringTemplate(n.to_string())])
        }
        Value::Null => {
            Ok(vec![])
        }
        _ => Ok(vec![]),
    }
}

/// Parse a switch operation from a YAML mapping key and value.
///
/// Form 1: `switch($quality): { "HT": [...], "LC": [...], default: [...] }`
/// Form 2: `switch: { "HT": "high", "LC": "low" }`
fn parse_switch_operation(key: &str, value: &Value) -> Result<Operation> {
    // Parse input variable from key
    let input = if key == "switch" {
        None // switch on current pipeline value
    } else if key.starts_with("switch(") && key.ends_with(')') {
        let inner = &key["switch(".len()..key.len() - 1];
        let trimmed = inner.trim();
        // Strip quotes if present
        let var = if (trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\''))
        {
            trimmed[1..trimmed.len() - 1].to_string()
        } else {
            trimmed.to_string()
        };
        Some(var)
    } else {
        bail!("Invalid switch syntax: {}", key);
    };

    // Parse cases from value (must be a Mapping)
    let mapping = value.as_mapping()
        .with_context(|| format!("switch cases must be a mapping, got: {:?}", value))?;

    let mut cases = Vec::new();
    let mut default_case = None;

    for (k, v) in mapping {
        let case_key = yaml_value_to_string(k);
        if case_key == "default" {
            default_case = Some(parse_pipeline_value(v)?);
        } else {
            let pipeline = parse_pipeline_value(v)?;
            cases.push((case_key, pipeline));
        }
    }

    Ok(Operation::Switch {
        input,
        cases,
        default_case,
    })
}

/// Parse a single operation string like "col("name")", "split(";")", etc.
pub fn parse_operation(s: &str) -> Result<Operation> {
    let s = s.trim();

    // capitalize, upcase, downcase (no args)
    match s {
        "capitalize" => return Ok(Operation::Capitalize),
        "upcase" => return Ok(Operation::Upcase),
        "downcase" => return Ok(Operation::Downcase),
        _ => {}
    }

    // Function call: func_name(args...)
    if let Some(paren_pos) = s.find('(') {
        if s.ends_with(')') {
            let func_name = &s[..paren_pos];
            let args_str = &s[paren_pos + 1..s.len() - 1];

            return match func_name {
                "col" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Col(arg))
                }
                "split" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Split(arg))
                }
                "prepend" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Prepend(arg))
                }
                "append" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Append(arg))
                }
                "join" => {
                    let args = parse_multi_args(args_str)?;
                    Ok(Operation::Join(args))
                }
                "skip" => {
                    let args = parse_multi_args(args_str)?;
                    Ok(Operation::Skip(args))
                }
                "replace" => {
                    let args = parse_multi_args(args_str)?;
                    if args.len() != 2 {
                        bail!("replace() requires exactly 2 arguments");
                    }
                    Ok(Operation::Replace(args[0].clone(), args[1].clone()))
                }
                "delete" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Delete(arg))
                }
                "pick" => {
                    let arg = parse_single_string_arg(args_str)?;
                    let n: usize = arg.parse()
                        .map_err(|_| anyhow::anyhow!("pick() argument must be an integer, got: {}", arg))?;
                    Ok(Operation::Pick(n))
                }
                "lang" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Lang(arg))
                }
                "datatype" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Datatype(arg))
                }
                "source" => {
                    // source is handled at the subject rule level, but parse anyway
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::StringTemplate(arg))
                }
                // tsv() is an alias for col() in older syntax
                "tsv" | "csv" => {
                    let arg = parse_single_string_arg(args_str)?;
                    Ok(Operation::Col(arg))
                }
                "switch" => {
                    // switch is complex; for now, parse the argument
                    let arg = parse_single_string_arg(args_str).unwrap_or_default();
                    Ok(Operation::VarRef(format!("${}", arg)))
                }
                _ => {
                    bail!("Unknown function: {}", func_name);
                }
            };
        }
    }

    // Variable reference: $var_name
    if s.starts_with('$') && !s.contains(' ') {
        return Ok(Operation::VarRef(s.to_string()));
    }

    // String template (may contain $var references): "text with $var"
    if s.contains('$') {
        return Ok(Operation::StringTemplate(s.to_string()));
    }

    // Plain string (constant)
    Ok(Operation::StringTemplate(s.to_string()))
}

/// Parse source("path"[, format[, table]]) call from a string
fn parse_source_call(s: &str) -> Option<(String, Option<String>)> {
    let s = s.trim();
    if s.starts_with("source(") && s.ends_with(')') {
        let args_str = &s[7..s.len() - 1];
        let args = parse_multi_args(args_str).ok()?;
        let path = args.first()?.clone();
        let format = args.get(1).cloned();
        Some((path, format))
    } else {
        None
    }
}

/// Parse a single quoted string argument
fn parse_single_string_arg(s: &str) -> Result<String> {
    let s = s.trim();
    // Remove surrounding quotes if present
    if (s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')) {
        Ok(s[1..s.len() - 1].to_string())
    } else if s.starts_with('/') && s.ends_with('/') && s.len() >= 2 {
        // /regex/ syntax — strip delimiters, pass pattern as-is
        Ok(s[1..s.len() - 1].to_string())
    } else if s.starts_with('$') {
        // Variable reference as argument
        Ok(s.to_string())
    } else {
        Ok(s.to_string())
    }
}

/// Parse multiple comma-separated arguments (may be quoted strings or $vars)
fn parse_multi_args(s: &str) -> Result<Vec<String>> {
    let s = s.trim();
    if s.is_empty() {
        return Ok(vec![]);
    }

    let mut args = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut was_quoted = false;  // track if this arg was explicitly quoted
    let mut quote_char = '"';

    for ch in s.chars() {
        if in_quotes {
            if ch == quote_char {
                in_quotes = false;
            } else {
                current.push(ch);
            }
        } else {
            match ch {
                '"' | '\'' | '/' => {
                    in_quotes = true;
                    was_quoted = true;
                    quote_char = ch;
                }
                ',' => {
                    let trimmed = current.trim().to_string();
                    if was_quoted || !trimmed.is_empty() {
                        args.push(trimmed);
                    }
                    current.clear();
                    was_quoted = false;
                }
                _ => {
                    current.push(ch);
                }
            }
        }
    }

    let trimmed = current.trim().to_string();
    if was_quoted || !trimmed.is_empty() {
        args.push(trimmed);
    }

    Ok(args)
}

fn yaml_value_to_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        _ => format!("{:?}", value),
    }
}
