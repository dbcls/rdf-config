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
    /// Things this predicate points to: named leaf objects and/or nested
    /// blank nodes, in declaration order.
    pub children: Vec<ObjectSpec>,
}

/// One child under a predicate.
///
/// In model.yaml a predicate's value is a list whose entries are either
/// `objName: value` (a named leaf) or `[]: <body>` (an anonymous blank
/// node). `ObjectSpec` captures that choice and makes blank nodes recursive:
/// a blank node has its own predicates, which in turn have their own
/// children, to any depth.
#[derive(Debug, Clone)]
pub enum ObjectSpec {
    /// A named leaf object: `objName: value`.
    Leaf(ObjectDef),
    /// An anonymous blank node `[]` with its own nested predicates.
    Blank(BlankNodeDef),
}

#[derive(Debug, Clone)]
pub struct ObjectDef {
    pub name: String,
    pub value_type: ObjectValueType,
    pub example_values: Vec<String>,
}

/// An anonymous blank node `[]` in model.yaml.
///
/// Structurally this is a subject without a name or example URIs: it carries
/// `rdf:type` declarations (from `a:` entries) and a list of predicates,
/// each of which may again contain nested blank nodes.
///
/// Example (CCLE): `faldo:begin → [] → { a: faldo:ExactPosition,
/// faldo:position → ccle_snp_start_pos, faldo:reference → ccle_snp_start_reference }`
#[derive(Debug, Clone)]
pub struct BlankNodeDef {
    pub rdf_types: Vec<String>,         // rdf:type values for this blank node
    pub predicates: Vec<PredicateDef>,  // predicates (excluding rdf:type)
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
    /// Value is a date literal (the model.yaml example looked like a date,
    /// e.g. `1973-10-22`). Emitted as `"..."^^xsd:date`.
    LiteralDate,
    /// Value is a date-and-time literal (example looked like
    /// `1973-10-22T09:15:00`). Emitted as `"..."^^xsd:dateTime`.
    LiteralDateTime,
    /// Value is a time-of-day literal (example looked like `09:15:00`).
    /// Emitted as `"..."^^xsd:time`.
    LiteralTime,
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

// ─── inferred datatypes ───

/// The XSD date/time datatype IRIs, written in full rather than as `xsd:`
/// CURIEs because these datatypes are inferred by the tool, not written by
/// the user: prefix.yaml is not guaranteed to declare an `xsd` prefix. Every
/// serializer compacts a full IRI back to a CURIE when a matching prefix
/// exists, so declaring `xsd` still yields `^^xsd:date` output.
pub const XSD_DATE: &str = "http://www.w3.org/2001/XMLSchema#date";
pub const XSD_DATE_TIME: &str = "http://www.w3.org/2001/XMLSchema#dateTime";
pub const XSD_TIME: &str = "http://www.w3.org/2001/XMLSchema#time";

/// Whether `s` is a valid `xsd:date` lexical form: `[-]YYYY[Y…]-MM-DD`
/// with an optional trailing timezone (`Z`, `+hh:mm` or `-hh:mm`).
///
/// This and its `dateTime` / `time` siblings are each used in two places,
/// deliberately with the same rule: `model.yaml` parsing calls them on an
/// object's example value to decide the object's type, and the engine calls
/// them on each runtime value to decide whether that value can actually carry
/// the datatype. A value that fails falls back to a plain string literal
/// rather than being emitted as an ill-typed literal.
///
/// The checks are strict about calendar and clock validity (month 1–12, day
/// within the month with February adjusted for leap years, hour 0–23 plus the
/// legal end-of-day `24:00:00`), so a value such as `2023-02-30` or
/// `25:00:00` is not recognized.
pub fn is_xsd_date_lexical(s: &str) -> bool {
    let (body, timezone) = split_timezone_suffix(s);
    is_date_body(body) && is_valid_timezone(timezone)
}

/// Recognize a date-and-time value and return it in the canonical
/// `xsd:dateTime` lexical form, or `None` when `s` is not one.
///
/// Both the canonical `T` separator (`1973-10-22T09:15:00`) and a single
/// space (`1973-10-22 09:15:00`) are accepted on input, because the space
/// form is what SQL databases and many exported tables produce. `xsd:dateTime`
/// itself permits only `T`, so the space is rewritten before the value is
/// emitted — returning the normalized string rather than a bare `bool` is
/// what keeps the serialized literal well-typed.
pub fn normalize_xsd_date_time(s: &str) -> Option<String> {
    let (body, timezone) = split_timezone_suffix(s);
    let (date, time) = body
        .split_once('T')
        .or_else(|| body.split_once(' '))?;
    if is_date_body(date) && is_time_body(time) && is_valid_timezone(timezone) {
        Some(format!("{}T{}{}", date, time, timezone))
    } else {
        None
    }
}

/// Whether `s` is a date-and-time value, in either the canonical `T` form or
/// the space-separated form. Used by model.yaml parsing, where only the
/// classification matters; the engine calls [`normalize_xsd_date_time`]
/// instead because it needs the canonical string to emit.
pub fn is_xsd_date_time_lexical(s: &str) -> bool {
    normalize_xsd_date_time(s).is_some()
}

/// Whether `s` is a valid `xsd:time` lexical form: `hh:mm:ss` with an
/// optional fractional part (`09:15:00.5`) and an optional timezone.
pub fn is_xsd_time_lexical(s: &str) -> bool {
    let (body, timezone) = split_timezone_suffix(s);
    is_time_body(body) && is_valid_timezone(timezone)
}

/// Split a trailing timezone off a date/time lexical form, returning the
/// remaining body and the timezone (empty when there is none).
///
/// The suffix is matched from the end rather than by scanning forward for
/// `Z` / `+` / `-`, because a date body is itself full of `-` separators and
/// may start with one (a BCE year). A numeric timezone is always exactly the
/// six characters `±hh:mm`, so it is recognized by shape.
fn split_timezone_suffix(s: &str) -> (&str, &str) {
    if let Some(body) = s.strip_suffix('Z') {
        return (body, "Z");
    }
    if let Some(cut) = s.len().checked_sub(6) {
        if cut > 0 && s.is_char_boundary(cut) {
            let (body, tail) = s.split_at(cut);
            let bytes = tail.as_bytes();
            if (bytes[0] == b'+' || bytes[0] == b'-') && bytes[3] == b':' {
                return (body, tail);
            }
        }
    }
    (s, "")
}

/// Whether `s` is a `[-]YYYY[Y…]-MM-DD` date, with any timezone already
/// stripped by [`split_timezone_suffix`].
fn is_date_body(s: &str) -> bool {
    // A leading `-` marks a BCE year; the rest is parsed identically.
    let s = s.strip_prefix('-').unwrap_or(s);

    // Year: four or more digits, with no extra leading zero beyond four.
    let Some((year_str, rest)) = s.split_once('-') else {
        return false;
    };
    if year_str.len() < 4 || !is_all_digits(year_str) {
        return false;
    }
    if year_str.len() > 4 && year_str.starts_with('0') {
        return false;
    }

    // Month and day: exactly two digits each.
    let Some((month_str, day_str)) = rest.split_once('-') else {
        return false;
    };
    if !is_two_digits(month_str) || !is_two_digits(day_str) {
        return false;
    }

    let (Ok(year), Ok(month), Ok(day)) = (
        year_str.parse::<i64>(),
        month_str.parse::<u32>(),
        day_str.parse::<u32>(),
    ) else {
        return false;
    };
    (1..=12).contains(&month) && day >= 1 && day <= days_in_month(year, month)
}

/// Whether `s` is an `hh:mm:ss[.fff…]` time of day, with any timezone
/// already stripped by [`split_timezone_suffix`].
fn is_time_body(s: &str) -> bool {
    let mut parts = s.splitn(3, ':');
    let (Some(hour_str), Some(minute_str), Some(second_str)) =
        (parts.next(), parts.next(), parts.next())
    else {
        return false;
    };

    // The seconds field may carry a fractional part of one or more digits.
    let (whole_seconds, fraction) = match second_str.split_once('.') {
        Some((whole, frac)) => (whole, Some(frac)),
        None => (second_str, None),
    };
    if !is_two_digits(hour_str) || !is_two_digits(minute_str) || !is_two_digits(whole_seconds) {
        return false;
    }
    if let Some(frac) = fraction {
        if frac.is_empty() || !is_all_digits(frac) {
            return false;
        }
    }

    let (Ok(hour), Ok(minute), Ok(second)) = (
        hour_str.parse::<u32>(),
        minute_str.parse::<u32>(),
        whole_seconds.parse::<u32>(),
    ) else {
        return false;
    };

    // `24:00:00` is the one legal hour-24 form: it denotes the end of the day
    // and must have zero minutes, seconds and fraction.
    if hour == 24 {
        return minute == 0
            && second == 0
            && fraction.is_none_or(|frac| frac.bytes().all(|b| b == b'0'));
    }
    hour <= 23 && minute <= 59 && second <= 59
}

/// Number of days in `month` (1–12) of `year`, using the proleptic Gregorian
/// leap rule that XML Schema mandates.
fn days_in_month(year: i64, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
            if leap { 29 } else { 28 }
        }
        _ => 0,
    }
}

/// Whether `tz` is an acceptable XML Schema timezone suffix: empty (no
/// timezone), `Z`, or a `+hh:mm` / `-hh:mm` offset no larger than 14:00.
fn is_valid_timezone(tz: &str) -> bool {
    if tz.is_empty() || tz == "Z" {
        return true;
    }
    let Some(offset) = tz.strip_prefix('+').or_else(|| tz.strip_prefix('-')) else {
        return false;
    };
    let Some((hour_str, minute_str)) = offset.split_once(':') else {
        return false;
    };
    if !is_two_digits(hour_str) || !is_two_digits(minute_str) {
        return false;
    }
    let (Ok(hours), Ok(minutes)) = (hour_str.parse::<u32>(), minute_str.parse::<u32>()) else {
        return false;
    };
    hours <= 14 && minutes <= 59 && (hours < 14 || minutes == 0)
}

fn is_all_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

fn is_two_digits(s: &str) -> bool {
    s.len() == 2 && is_all_digits(s)
}

// ─── convert.yaml types ───

#[derive(Debug, Clone)]
pub struct ConvertConfig {
    pub subject_rules: Vec<SubjectRule>,
}

#[derive(Debug, Clone)]
pub struct SubjectRule {
    pub name: String,                         // must match model subject name
    pub source_path: Option<String>,          // optional source() file path (1st arg)
    pub source_format: Option<SourceFormat>,  // optional source() format (2nd arg, e.g. :duckdb)
    pub source_table: Option<String>,         // optional source() table name (3rd arg, DuckDB only)
    pub pre_variables: Vec<VariableDef>,      // top-level variable definitions
    pub subject_pipeline: SubjectPipeline,
    pub object_variables: Vec<VariableDef>,
    pub object_rules: Vec<ObjectRule>,
}

/// Input file format, determined either explicitly via the 2nd arg of source()
/// or implicitly via file extension.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SourceFormat {
    Tsv,
    Csv,
    DuckDb,
    Sqlite,
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

/// A generated triple.
///
/// `subject_name` and `object_name` are optional back-pointers into model.yaml,
/// used solely by the JSON-LD serializer to substitute human-readable names
/// for IRIs in graph node keys. They are not part of the RDF triple's
/// identity and are ignored by Turtle output and deduplication.
#[derive(Debug, Clone)]
pub struct Triple {
    pub subject: String,  // full URI
    pub predicate: String, // CURIE or URI
    pub object: RdfTerm,
    /// model.yaml SubjectDef.name producing this triple (None for auto-gen,
    /// e.g. rdf:type triples emitted on referenced subjects).
    pub subject_name: Option<String>,
    /// model.yaml ObjectDef.name corresponding to this triple's predicate.
    /// None when the triple is an rdf:type / outer-bnode triple or otherwise
    /// has no associated ObjectDef.
    pub object_name: Option<String>,
}

/// Collected triples grouped by subject for Turtle output
pub type SubjectTriples = indexmap::IndexMap<String, Vec<(String, RdfTerm)>>;

/// Variables store
pub type Variables = HashMap<String, String>;
