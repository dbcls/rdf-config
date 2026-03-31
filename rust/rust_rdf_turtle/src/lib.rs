use magnus::{function, prelude::*, Error, Ruby, Value};
use oxrdf::{BlankNode, Literal, NamedNode, NamedOrBlankNode, Term, Triple};
use oxttl::TurtleSerializer;
use serde::Deserialize;
use serde_magnus::deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum InputLine {
    Prefix {
        prefix: String,
        iri: String,
    },
    Triple(TripleLine),
}

#[derive(Debug, Deserialize)]
struct TripleLine {
    s_kind: SubjectKind,
    s: String,
    p: String,
    o_kind: ObjectKind,
    o: String,

    #[serde(default)]
    lang: Option<String>,

    #[serde(default)]
    datatype: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum SubjectKind {
    Iri,
    Bnode,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ObjectKind {
    Iri,
    Bnode,
    LiteralPlain,
    LiteralLang,
    LiteralDt,
}

fn runtime_error(ruby: &Ruby, msg: impl Into<String>) -> Error {
    Error::new(ruby.exception_runtime_error(), msg.into())
}

fn build_subject(ruby: &Ruby, kind: &SubjectKind, value: &str) -> Result<NamedOrBlankNode, Error> {
    match kind {
        SubjectKind::Iri => {
            let node = NamedNode::new(value)
                .map_err(|e| runtime_error(ruby, format!("Invalid subject IRI: {e}")))?;
            Ok(node.into())
        }
        SubjectKind::Bnode => {
            let node = BlankNode::new(value).map_err(|e| {
                runtime_error(ruby, format!("Invalid subject blank node ID: {e}"))
            })?;
            Ok(node.into())
        }
    }
}

fn build_predicate(ruby: &Ruby, value: &str) -> Result<NamedNode, Error> {
    NamedNode::new(value)
        .map_err(|e| runtime_error(ruby, format!("Invalid predicate IRI: {e}")))
}

fn build_object(
    ruby: &Ruby,
    kind: &ObjectKind,
    value: &str,
    lang: Option<&str>,
    datatype: Option<&str>,
) -> Result<Term, Error> {
    match kind {
        ObjectKind::Iri => {
            if lang.is_some() || datatype.is_some() {
                return Err(runtime_error(
                    ruby,
                    "lang / datatype cannot be specified when o_kind=iri",
                ));
            }
            let node = NamedNode::new(value)
                .map_err(|e| runtime_error(ruby, format!("Invalid object IRI: {e}")))?;
            Ok(node.into())
        }
        ObjectKind::Bnode => {
            if lang.is_some() || datatype.is_some() {
                return Err(runtime_error(
                    ruby,
                    "lang / datatype cannot be specified when o_kind=bnode",
                ));
            }
            let node = BlankNode::new(value).map_err(|e| {
                runtime_error(ruby, format!("Invalid object blank node id: {e}"))
            })?;
            Ok(node.into())
        }
        ObjectKind::LiteralPlain => {
            if lang.is_some() || datatype.is_some() {
                return Err(runtime_error(
                    ruby,
                    "lang / datatype cannot be specified when o_kind=literal_plain",
                ));
            }
            Ok(Literal::new_simple_literal(value).into())
        }
        ObjectKind::LiteralLang => {
            if datatype.is_some() {
                return Err(runtime_error(
                    ruby,
                    "datatype cannot be specified when o_kind=literal_lang",
                ));
            }
            let lang = lang.ok_or_else(|| {
                runtime_error(ruby, "lang is required when o_kind=literal_lang")
            })?;
            let lit = Literal::new_language_tagged_literal(value, lang)
                .map_err(|e| runtime_error(ruby, format!("Invalid language tag: {e}")))?;
            Ok(lit.into())
        }
        ObjectKind::LiteralDt => {
            if lang.is_some() {
                return Err(runtime_error(
                    ruby,
                    "lang cannot be specified when o_kind=literal_dt",
                ));
            }
            let datatype = datatype.ok_or_else(|| {
                runtime_error(ruby, "datatype required when o_kind=literal_dt")
            })?;
            let dt = NamedNode::new(datatype)
                .map_err(|e| runtime_error(ruby, format!("Invalid datatype IRI: {e}")))?;
            Ok(Literal::new_typed_literal(value, dt).into())
        }
    }
}

fn generate_turtle(ruby: &Ruby, input: Value) -> Result<String, Error> {
    let records: Vec<InputLine> = deserialize(ruby, input)
        .map_err(|e| runtime_error(ruby, format!("Failed to deserialize arguments: {e}")))?;

    let mut builder = TurtleSerializer::new();
    let mut triple_start = None;

    for (idx, record) in records.iter().enumerate() {
        match record {
            InputLine::Prefix { prefix, iri } => {
                builder = builder.with_prefix(prefix, iri).map_err(|e| {
                    runtime_error(
                        ruby,
                        format!("Line {}: invalid prefix specification: {e}", idx + 1),
                    )
                })?;
            }
            InputLine::Triple(_) => {
                triple_start = Some(idx);
                break;
            }
        }
    }

    let Some(triple_start) = triple_start else {
        return Ok(String::new());
    };

    for (idx, record) in records.iter().enumerate().skip(triple_start) {
        if let InputLine::Prefix { .. } = record {
            return Err(runtime_error(
                ruby,
                format!("Line {}: prefix can only appear at the beginning", idx + 1),
            ));
        }
    }

    let mut serializer = builder.for_writer(Vec::new());

    for (idx, record) in records.into_iter().enumerate().skip(triple_start) {
        let line_no = idx + 1;

        let t = match record {
            InputLine::Triple(t) => t,
            InputLine::Prefix { .. } => unreachable!(),
        };

        let subject = build_subject(ruby, &t.s_kind, &t.s)
            .map_err(|e| runtime_error(ruby, format!("Line {line_no}: {e}")))?;
        let predicate = build_predicate(ruby, &t.p)
            .map_err(|e| runtime_error(ruby, format!("Line {line_no}: {e}")))?;
        let object = build_object(
            ruby,
            &t.o_kind,
            &t.o,
            t.lang.as_deref(),
            t.datatype.as_deref(),
        )
        .map_err(|e| runtime_error(ruby, format!("Line {line_no}: {e}")))?;

        let triple = Triple {
            subject,
            predicate,
            object,
        };

        serializer.serialize_triple(triple.as_ref()).map_err(|e| {
            runtime_error(
                ruby,
                format!("Line {line_no}: failed to serialize: {e}"),
            )
        })?;
    }

    let bytes = serializer.finish().map_err(|e| {
        runtime_error(ruby, format!("Failed to finalize Turtle output: {e}"))
    })?;

    String::from_utf8(bytes)
        .map_err(|e| runtime_error(ruby, format!("Failed to convert to UTF-8: {e}")))
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = ruby.define_module("RustRdfTurtle")?;
    module.define_singleton_method("generate_turtle", function!(generate_turtle, 1))?;
    Ok(())
}
