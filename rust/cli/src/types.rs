use std::collections::HashMap;

/// Prefix mapping: prefix name -> full IRI
pub type PrefixMap = indexmap::IndexMap<String, String>;

// ─── model.yaml types ───

/// The entire model: a list of subject definitions (order preserved).
#[derive(Debug, Clone)]
pub struct Model {
    pub subjects: Vec<SubjectDef>,
}

#[derive(Debug, Clone)]
pub struct SubjectDef {
    pub name: String,                   // CamelCase name
    pub example_uris: Vec<String>,      // example URIs (may be empty)
    pub rdf_types: Vec<String>,         // rdf:type values (CURIE or full URI)
    pub predicates: Vec<PredicateDef>,  // predicates (excluding rdf:type)
}

#[derive(Debug, Clone)]
pub struct PredicateDef {
    pub uri: String,       // predicate URI (CURIE or full)
    pub cardinality: Cardinality,
    pub objects: Vec<ObjectDef>,
    pub blank_node_groups: Vec<BlankNodeGroupDef>,
}

#[derive(Debug, Clone)]
pub struct ObjectDef {
    pub name: String,
    pub value_type: ObjectValueType,
    pub example_values: Vec<String>,
}

/// A blank node group: [] in model.yaml.
/// Example: `bp3:participant → [] → obo:BFO_0000051 → [pair0, pair1]`
#[derive(Debug, Clone)]
pub struct BlankNodeGroupDef {
    pub inner_predicate: String,    // e.g. "obo:BFO_0000051"
    pub objects: Vec<ObjectDef>,    // objects within the blank node
}

#[derive(Debug, Clone)]
pub enum ObjectValueType {
    /// Value is a URI (example was <...> or prefix:local)
    Uri,
    /// Value is a reference to another subject (value is a CamelCase subject name)
    Reference(String),
    /// Value is a list of references to other subjects
    ReferenceList(Vec<String>),
    /// Value is a literal string
    LiteralString,
    /// Value is a literal integer
    LiteralInteger,
    /// Value is a literal float
    LiteralFloat,
    /// Value is a literal boolean (true/false)
    LiteralBoolean,
    /// Value is a literal with language tag, e.g. "foo"@en
    LiteralLangString { lang: String },
    /// Value is a literal with datatype, e.g. "123"^^xsd:integer
    LiteralDatatype { datatype: String },
}

#[derive(Debug, Clone)]
pub enum Cardinality {
    ExactlyOne,         // no marker
    ZeroOrOne,          // ?
    ZeroOrMore,         // *
    OneOrMore,          // +
    Exact(usize),       // {n}
    Range(usize, usize), // {n,m}
}

// ─── convert.yaml types ───

#[derive(Debug, Clone)]
pub struct ConvertConfig {
    pub subject_rules: Vec<SubjectRule>,
}

#[derive(Debug, Clone)]
pub struct SubjectRule {
    pub name: String,                         // must match model subject name
    pub source_path: Option<String>,          // optional source() file path
    pub source_format: Option<String>,        // csv, tsv, duckdb
    pub pre_variables: Vec<VariableDef>,      // top-level variable definitions
    pub subject_pipeline: SubjectPipeline,
    pub object_rules: Vec<ObjectRule>,
}

#[derive(Debug, Clone)]
pub struct SubjectPipeline {
    pub variables: Vec<VariableDef>,  // variable definitions inside subject:
    pub steps: Vec<Operation>,         // pipeline steps for generating subject URI
}

#[derive(Debug, Clone)]
pub struct VariableDef {
    pub name: String,               // variable name (including $)
    pub pipeline: Vec<Operation>,   // operations to compute the value
}

#[derive(Debug, Clone)]
pub struct ObjectRule {
    pub name: String,             // object name from model.yaml
    pub pipeline: Vec<Operation>, // operations to compute the value
}

#[derive(Debug, Clone)]
pub enum Operation {
    /// col("column_name") - get column value
    Col(String),
    /// split("sep") - split value by separator
    Split(String),
    /// prepend("str") - prepend string (may contain $var)
    Prepend(String),
    /// append("str") - append string (may contain $var)
    Append(String),
    /// join(str1, str2, ..., sep) - join values with separator
    Join(Vec<String>),
    /// skip("val1", "val2", ...) - skip if value matches
    Skip(Vec<String>),
    /// replace(pattern, replacement)
    Replace(String, String),
    /// delete(pattern)
    Delete(String),
    /// pick(n) - extract the nth element (0-based) from a Multiple value
    Pick(usize),
    /// lang("tag") - add language tag
    Lang(String),
    /// datatype("type") - add datatype
    Datatype(String),
    /// capitalize
    Capitalize,
    /// upcase
    Upcase,
    /// downcase
    Downcase,
    /// Variable reference: $var_name
    VarRef(String),
    /// String template with variable interpolation: "prefix/$var/suffix"
    StringTemplate(String),
    /// Inline variable definition within a pipeline (name, sub-pipeline)
    InlineVarDef(String, Vec<Operation>),
    /// switch / switch($var) - conditional value mapping
    /// input: None = switch on current value, Some("$var") = switch on variable
    /// cases: vec of (match_value, pipeline)
    /// default_case: optional default pipeline
    Switch {
        input: Option<String>,
        cases: Vec<(String, Vec<Operation>)>,
        default_case: Option<Vec<Operation>>,
    },
}

// ─── Runtime types ───

/// A value that flows through the pipeline.
/// Can be a single value or multiple values (after split).
#[derive(Debug, Clone)]
pub enum PipelineValue {
    Single(String),
    Multiple(Vec<String>),
    /// Signal to skip this triple
    Skip,
}

/// An RDF term for Turtle output
#[derive(Debug, Clone)]
pub enum RdfTerm {
    Uri(String),           // full URI like http://...
    Curie(String),         // prefix:local
    BlankNode(String),     // blank node ID like "_:b1"
    LiteralString(String),
    LiteralInteger(i64),
    LiteralFloat(String),
    LiteralBoolean(bool),
    LiteralLangString(String, String),     // value, lang
    LiteralDatatype(String, String),       // value, datatype CURIE
}

/// A generated triple
#[derive(Debug, Clone)]
pub struct Triple {
    pub subject: String,  // full URI
    pub predicate: String, // CURIE or URI
    pub object: RdfTerm,
}

/// Collected triples grouped by subject for Turtle output
pub type SubjectTriples = indexmap::IndexMap<String, Vec<(String, RdfTerm)>>;

/// Variables store
pub type Variables = HashMap<String, String>;
