use rdf::graph::Graph;
use rdf::namespace::Namespace;
use rdf::triple::Triple;
use rdf::uri::Uri;
use rdf::writer::rdf_writer::RdfWriter;
use rdf::writer::turtle_writer::TurtleWriter;
use serde::Deserialize;
use std::error::Error;
use std::io::{self, BufRead, BufReader, BufWriter, Read, Write};


#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum InputRow {
    #[serde(rename = "prefix")]
    Prefix {
        prefix: String,
        iri: String,
    },

    #[serde(rename = "triple")]
    Triple {
        s_kind: String,
        s: String,
        p: String,
        o_kind: String,
        o: String,
        datatype: Option<String>,
        lang: Option<String>,
    },
}

pub fn write_turtle_with_rdf_rs<R: Read, W: Write>(
    reader: R,
    mut writer: W,
) -> Result<(), Box<dyn Error>> {
    let mut graph = Graph::new(None);

    let stream = serde_json::Deserializer::from_reader(reader).into_iter::<InputRow>();

    for item in stream {
        match item? {
            InputRow::Prefix { prefix, iri } => {
                graph.add_namespace(&Namespace::new(prefix, Uri::new(iri)));
            }

            InputRow::Triple {
                s_kind,
                s,
                p,
                o_kind,
                o,
                datatype,
                lang,
            } => {
                let subject = match s_kind.as_str() {
                    "iri" => graph.create_uri_node(&Uri::new(s)),
                    "bnode" => graph.create_blank_node_with_id(s),
                    other => return Err(format!("invalid s_kind: {other}").into()),
                };

                let predicate = graph.create_uri_node(&Uri::new(p));

                let object = match o_kind.as_str() {
                    "iri" => graph.create_uri_node(&Uri::new(o)),
                    "bnode" => graph.create_blank_node_with_id(o),
                    "literal_plain" => graph.create_literal_node(o),
                    "literal_lang" => {
                        let lang = lang.ok_or("literal_lang requires lang")?;
                        graph.create_literal_node_with_language(o, lang)
                    }
                    "literal_dt" => {
                        let dt = datatype.ok_or("literal_dt requires datatype")?;
                        graph.create_literal_node_with_data_type(o, &Uri::new(dt))
                    }
                    other => return Err(format!("invalid o_kind: {other}").into()),
                };

                let triple = Triple::new(&subject, &predicate, &object);
                graph.add_triple(&triple);
            }
        }
    }

    let turtle = TurtleWriter::new(graph.namespaces()).write_to_string(&graph)?;
    writer.write_all(turtle.as_bytes())?;
    writer.flush()?;
    Ok(())
}

pub fn run_from_stdio() -> Result<(), Box<dyn Error>> {
    let stdin = io::stdin();
    let stdout = io::stdout();

    let reader = BufReader::new(stdin.lock());
    let writer = BufWriter::new(stdout.lock());

    write_turtle_with_rdf_rs(reader, writer)
}
