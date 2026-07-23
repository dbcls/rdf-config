# RDF-config specification

## endpoint.yaml

Describe the SPARQL endpoint using the notation below.

```yaml
endpoint: http://example.org/sparql
```

Specify the default endpoint with `endpoint:`. If you want to describe multiple endpoints that hold the same data, use the notation below. If you write the name of the graph containing the data for each endpoint, it will be used in the FROM clause of the generated SPARQL query.

```yaml
endpoint:
  - http://example.org/sparql  # primary SPARQL endpoint
  - graph:
    - http://example.org/graph/1
    - http://example.org/graph/2
    - http://example.org/graph/3

another_endpoint:
  - http://another.org/sparql  # backup SPARQL endpoint
  - graph:
    - http://another.org/graph/A
    - http://another.org/graph/B
```

## prefix.yaml

Always define the CURIE/QName prefixes used in the RDF data model with the notation below.

```yaml
rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
rdfs: <http://www.w3.org/2000/01/rdf-schema#>
xsd: <http://www.w3.org/2001/XMLSchema#>
dc: <http://purl.org/dc/elements/1.1/>
dct: <http://purl.org/dc/terms/>
skos: <http://www.w3.org/2004/02/skos/core#>
```

## model.yaml

The RDF data model is fundamentally represented as nested arrays following the YAML-compliant structure below (in order to preserve order and allow duplicate occurrences). Note that misaligned indentation causes an error (spaces and tabs should not be mixed at the start of a line), and that a `:` must be appended to the end of each subject, predicate, and object since each of them becomes a hash key.

```yaml
- SubjectName subject_example1 subject_example2:
  - predicate:
    - object_name1: object_example1
  - predicate:
    - object_name2: object_example2
    - object_name3: object_example3
    - object_name4: object_example4
  - predicate:
    - []:  # blank node
      - predicate:
        - object_name: object_example
    - []:
      - predicate:
        - []:  # nested blank node
          - predicate:
            - object_name: object_example
```

The subject example, predicate, and object example are written as a URI (`<http://...>`) or a CURIE/QName (`prefix:local_part`). The object example can be a literal, and if it's truly necessary, multiple examples may be specified. Note that a blank node is represented by `[]`.

The subject name and object name become the variable names used when displaying SPARQL search results, so give them names whose meaning is easy to understand. The subject name should use CamelCase, and the object name should use snake_case.

For anyone, it's tedious and unproductive to have to assume that a variable named `name` holds a date of birth, or to wonder what a value of 42 stored in a variable named `obj1` actually means. It would not be an exaggeration to say that the most important point in RDF-config is setting appropriate variable names that express the meaning of the value. Also, just as tabular data where the same column name appears multiple times is hard to work with unless you rename the columns while considering the difference in meaning, by the same analogy the key point is to make each "variable name" both "unique" and "easy to understand" within the model.yaml file.

### Subject

Following the subject name, write example subject URIs separated by spaces (optional). Always specify `rdf:type` (`a`) for the subject. It is further strongly recommended to also add `rdfs:label` or `dct:identifier`.

When the subject is a URI:
```yaml
- Entry <http://example.org/mydb/entry/1>:
  - a: mydb:Entry  # when there is a single type
  - a:             # when there are multiple types
    - mydb:Entry
    - hoge:Fuga
  - rdf:type:      # if writing without using the shorthand `a` for rdf:type, define rdf: in prefix.yaml
    - mydb:Entry
    - hoge:Fuga
  - rdfs:label:
    - label: "1"
  - dct:identifier:
    - id: 1
```

When the subject is a CURIE/QName:
```yaml
- Entry mydb:1:
  - a: mydb:Entry
(and so on)
```

When the subject is a blank node:
```yaml
- []:
  - a: mydb:Entry
(and so on)
```

For the subject, three things need to be given: the type name (variable name) in GraphQL, the type (URI) in RDF, and a sample example (URI); both the RDF type and the sample example may be plural. If you want to list multiple sample examples, enumerate them separated by spaces.

```yaml
- Entry mydb:1 mydb:2:
  - a: mydb:Entry
(and so on)
```

### Predicate

Enumerate as an array the predicates hanging off the subject, written as a URI (`<http://...>`) or CURIE/QName (`prefix:local_part`).

You can express a constraint on the allowed number of occurrences of the object corresponding to a predicate by appending one of the following symbols to the end of the predicate.

* none: no constraint is checked (interpreted as assuming there is "one" corresponding value, i.e. `{1}`)
* `?`: zero or one (when the corresponding value may be "absent" or "limited to one" → becomes an OPTIONAL clause)
* `*`: zero or more (when the corresponding value may be "absent" or "possibly multiple" → becomes an OPTIONAL clause)
* `+`: one or more (when the corresponding value should "exist" and "may possibly be multiple")
* `{n}`: exactly n (when the corresponding value is limited to exactly "n")
* `{n,m}`: from n to m (when the corresponding value is limited to between "n" and "m" inclusive)

This designation is used both to determine whether the SPARQL query becomes an OPTIONAL clause and for RDF validation via ShEx.

```yaml
- Subject my:subject:
  - a: my:Class
  - my:predicate1?:
    - string_label: "This is my value"
  - my:predicate2*:
    - integer_value: 123
  - my:predicate3+:
    - date_value: 2020-05-21
  - my:predicate4{2}:
    - integer_value: 123, 456
  - my:predicate5{3,5}:
    - integer_value: 123, 456, 789
```

However, note that because RDF data follows the open world assumption, it cannot be guaranteed that there is always exactly one value corresponding to a predicate (i.e., that there are not multiple values). Therefore, at the SPARQL level there is no distinction between "`predicate` and `predicate+`" nor between "`predicate?` and `predicate*`".

### Object

For the object hanging off a predicate, write the object's name and its example. Since the object name is used as the variable name in SPARQL queries, it must be set to something unique within the model.yaml file, written in snake_case.

The object example may be omitted, but it is recommended to always include it in order to make the schema diagram easier to understand. Its value has its type inferred by the YAML parser, so strings (which don't necessarily need to be quoted as far as YAML is concerned), numbers, dates, and so on can be written as-is. Since URIs are treated as strings in YAML, RDF-config specially interprets strings enclosed in `<>` and CURIE/QName (whose prefix is defined in prefix.yaml) as URIs.

```yaml
- Subject my:subject:
  - a: my:Class
  - my:predicate1:
    - string_label: "This is my value"
  - my:predicate2:
    - integer_value: 123
  - my:predicate3:
    - float_value: 123.45
  - my:predicate4:
    - curie: my:sample123
  - rdfs:seeAlso:
    - xref: <http://example.org/sample/uri>
```

If an object refers to another RDF model, write the name of the referenced subject as the object.
(TODO: extend this so that commonly usable data models such as FALDO can be referenced externally)

```yaml
- Subject my:subject:
  - my:refer:
    - other_subject: OtherSubject  # a subject name used as a subject within the same model.yaml
- OtherSubject my:other_subject:
  - a: my:OtherClass
```

If the object example spans multiple lines, you can use the YAML `|` notation so that the indented part is treated as a multi-line literal. However, note that if it's too long it may not be displayable, or the display in the schema diagram may break.

```yaml
- Subject my:subject:
  - my:predicate:
    - value: |
        long long line of
         example explanation
        in detail
```

Language tags (such as `"hoge"@en`, `"ほげ"@ja`) can apparently be specified as follows.
(It must be enclosed in `''`, otherwise it results in a YAML error)

```yaml
- Subject my:subject:
  - my:predicate:
    - name: '"hoge"@en'
```

Type designation for a literal using `^^` (such as `"123"^^xsd:string`) can apparently be specified as follows.
(It must be enclosed in `''`, otherwise it results in a YAML error)

```yaml
- Subject my:subject:
  - my:predicate:
    - myvalue: '"123"^^xsd:integer'
```

## schema.yaml

This file is used when you want to draw a schema diagram of only the main parts when the model is complex — that is, when generating a schema diagram from a subset of the model — and is written in the following YAML format. Note that the overall schema diagram can be generated even without this file.

```yaml
schema_name1:
  description: A list of subject names and object names to include in the schema diagram
  variables: [ subject_name1, subject_name2, object_name1, object_name2, object_name3 ]

schema_name2:
  description: If objects are specified, a diagram is created showing only those objects hanging from the corresponding subject
  variables: [ object_name1, object_name2, object_name3 ]

schema_name3:
  description: If only subjects are specified, a diagram is created showing all objects hanging from those subjects
  variables: [ subject_name1, subject_name2 ]

schema_name4:
  description: Specify only the title to be shown on the schema diagram
```

## sparql.yaml

This is a file where you can configure multiple SPARQL queries, written in the following YAML format.

In RDF-config, the required property paths are identified from the names of the target objects and the SPARQL query is generated automatically, so you only need to list, in `variables`, the variable names you want as the result. When creating a query that takes part of the value as an argument, such as an ID or a name, set in `parameters` the variable name to which the value should be assigned and its default value.

```yaml
query_name:
  description: A description of what this SPARQL query does
  variables: [ foo, bar, ... ]  # list the names (variable names) of the objects to be SELECTed in SPARQL

another_query_name_taking_arguments:
  description: A description of what this SPARQL query does
  variables: [ foo, bar, ... ]  # list the names (variable names) of the objects to be SELECTed in SPARQL
  parameters:
    object_name: default_value

another_query_name_taking_options:
  description: A description of what this SPARQL query does
  variables: [ foo, bar, ... ]  # list the names (variable names) of the objects to be SELECTed in SPARQL
  options:
    distinct: true   # SELECT DISTINCT ...
    limit: 500       # to remove the LIMIT clause, specify false
    offset: 200
    order_by:        # ORDER BY ?var1 DESC(?var2) ?var3
    - var1: asc      # ascending sort
    - var2: desc     # descending sort
    - var3           # asc may be omitted
```

As a point of caution, if a subject having a variable name is reused as an object name hanging off multiple subjects, the generated SPARQL assumes that variable has the same value at every occurrence, so you may need to manually adjust the variable names as needed to get the intended SPARQL.

## convert.yaml

This file defines the rules (processing steps) for generating RDF or JSON-LD from CSV files, TSV files, DuckDB, or SQLite3, and is written in the following YAML format.

```yaml
- subject_name1:
  # processing to set the source file path or to set values into variables
  - process1-1
  - process1-2
  - process1-3
  - subject: # describe below the rule for generating the value of subject_name1
    - subject_name1_generation_process1
    - subject_name1_generation_process2
    # ... the generation processes for subject_name1 continue below
  - objects: # describe below the rules for generating the values of the objects tied to subject_name1
    - object_name1-1: object_name1-1_generation_process
    - object_name1-2: # if there are multiple generation processes, write them as an array like below
      - object_name1-2_generation_process1
      - object_name1-2_generation_process2
      - object_name1-2_generation_process3
    - object_name1-3: object_name1-3_generation_process
    # ... the generation rules for objects tied to subject_name1 continue below

- subject_name2:
  # processing to set the source file path or to set values into variables
  - process2-1
  - process2-2
  - process2-3
  - subject:
    # describe the generation rule for subject_name2
    ...
  - objects:
    - object_name2-1: object_name2-1_generation_process
    - object_name2-2:
      - object_name2-2_generation_process1
      - object_name2-2_generation_process2
      - object_name2-2_generation_process3
    - object_name2-3: object_name2-3_generation_process
    # ... the generation rules for objects tied to subject_name2 continue below

# ... the generation rules for subjects in model.yaml continue below
```

The subject-name or object-name part refers to the subject name or object name as written in model.yaml.
The generation process part describes the rules for generating the value (the RDF resource URI or property value) corresponding to the key, which is a subject name or object name.
The actual generation process is a method written in Ruby, which has the function of returning the value obtained by running the generation process (the Ruby method) on the input value.
The rule for generating a subject's URI or an object's value consists of one or more generation processes; when there are multiple generation processes, the value-generation rule is specified as an array of generation processes.
In this case, the generation processes are executed in the order of the array elements, and for each generation process, the value being processed (the input value) is the value generated by the previous generation process.
Then, the value produced by running the last generation process becomes the value corresponding to that key.

For example, in the `convert.yaml` example above, three generation processes are described for `object_name1-2` of `subject_name1`; this is a setting that generates the value of object 1-2 as follows.
1. Generation process 1 of object_name1-2 is executed.<br/>Normally, the first generation process is `col(column_name)`, a process that gets the value of a column.
2. Generation process 2 of object_name1-2 is executed, taking as input the value generated by generation process 1 above.
3. Generation process 2 of object_name1-3 is executed, taking as input the value generated by generation process 2 above.
4. The value from step 3 above becomes the value of object_name1-2 (the property value).

RDF-config provides the following processes as generation processes.

| Process name | Process content |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| append       | `append(str)`<br/>Appends `str` to the end of the value. |
| capitalize   | `capitalize`<br/>Capitalizes the first letter of the value (a string). |
| col          | `col(col_name)`<br/>Gets the value of the `col_name` column in a CSV, TSV, DuckDB, or SQLite3 source. |
| datatype     | `datatype(type)`<br/>Specify an RDF data type such as `xsd:date` for `type`, so that the object's literal value has that data type. |
| delete       | `delete(pattern)`<br/>Deletes the part matching `pattern`. `pattern` can be a string or a regular expression. |
| downcase     | `downcase`<br/>Converts the entire string to lowercase. |
| join         | `join(str1, str2, ..., strN, sep)`<br/>Concatenates `str1` through `strN`, inserting the string `sep` between them. |
| lang         | `lang(lang_tag)`<br/>Sets an RDF language tag ("ja", "en", etc.) on the object's literal value. |
| prepend      | `prepend(str)`<br/>Adds the string given as the argument to the beginning of the value. |
| replace      | `replace(pattern, replace)`<br/>Replaces the part matching `pattern` with `replace`.<br/>`pattern` can be a string to replace or a regular expression; if a string is given, it only matches exactly the same string. |
| source       | `source(file_path[, file_format[, table_name]])`<br/>Specifies the path of the file to be converted, the file format, and the table name (for DuckDB).<br/>The file format can be `:csv`, `:tsv`, `:duckdb`, or `sqlite3`; `:csv` and `:tsv` can be omitted (in which case the format is determined from the input file's extension).<br/>When `:duckdb` or `:sqlite3` is specified, `table_name` must also be specified. |
| skip         | `skip(str1, str2, ...)`<br/>Specify any number of strings as arguments; if the value being processed matches one of the specified strings, no triple with that value as the object is generated. |
| split        | `split(sep)`<br/>Splits the value by `sep`. |
| switch       | `switch(exp)`<br/>"val1":<br/>&nbsp;&nbsp;the conversion process when the value of switch(exp) is val1<br/>"val2":<br/>&nbsp;&nbsp;the conversion process when the value of switch(exp) is val2<br/>...<br/>default:<br/>&nbsp;&nbsp;the conversion process when the value of switch(exp) is none of the above<br/><br/>References the value with `switch(exp)`, and branches the conversion process based on that value.<br/>`switch(exp)` can be written in the following ways:<br/><ul><li>`switch`: references the value currently being processed at that point.</li><li>`switch("col_name")`: references the value of the "col_name" column of the row currently being processed.</li><li>`switch($var_name)`: references the value of the variable `$var_name`.</li></ul> |
| upcase       | `upcase`<br/>Converts the entire string to uppercase. |

If you want to run a process other than those above, you can add your own custom process.
The process itself is a Ruby method; save the Ruby file describing the process under `lib/rdf-config/convert/macros`.
In that case, the file name should be `process_name.rb`.

### Subject generation rule
Write the subject name from model.yaml as the top-level key of convert.yaml, and set, under a key called `subject`, the rule for generating that subject's resource URI.
Below is an example description of convert.yaml for a subject.

```yaml
- MySubject:
  - source("/path/to/csv_file.csv")
  - subject: 
    - col("id_column")
    - prepend("http://example.org/my_subject/")
```

In this case, the value of `MySubject` is generated as follows.
1. Set the source CSV file to `/path/to/csv_file.csv`.
2. Get the value of the `id_column` column of the `/path/to/csv_file.csv` file.
3. Prepend `http://example.org/my_subject/` to the value obtained above.

For example, if the value of the `id_column` column is 1, the value of `MySubject` (the resource URI) is generated as follows.
1. Get the value of the `id_column` column of the CSV, which is 1.
2. Prepend `http://example.org/my_subject/` to the value 1 above.

As a result, the resource URI of MySubject becomes
http://example.org/my_subject/1

### Object value generation rules
Under a key called `objects`, describe the rules for generating the RDF values (property values) of the objects tied to the subject.
For each key of the array elements under `- objects:`, write the corresponding object name from model.yaml.

Below is an example description of convert.yaml for objects.
```yaml
- MySubject:
  - source("/path/to/csv_file.csv")
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - my_label:
      - csv("label")
      - lang("ja")
    - my_date:
      - csv("date")
      - datatype("xsd:date")
```

The generation rules for the objects (my_label, my_date) in the convert.yaml above can be interpreted as follows.
* The property value of my_label = an RDF literal value consisting of the value of the CSV file's `label` column with the RDF language tag "ja" attached
* The property value of my_date = an RDF literal value consisting of the value of the CSV file's `date` column with the data type "xsd:date" attached

#### Attaching RDF language tags and data types
In the example above, the process of attaching an RDF language tag or data type is written in convert.yaml, but
if a language tag or data type is already attached to the object's example value in model.yaml, that is
referenced to determine the property value's language tag or data type, so it is not necessary to write the process for attaching a language tag or data type in convert.yaml.

For example, suppose that in model.yaml a language tag or data type is attached to the object's example value, as below.
model.yaml (with a language tag or data type attached to the object's example value)
```yaml
- MySubject <http://example.org/my_subject/1>:
  - my:label:
    - my_label "マイラベル"@ja
  - my:date:
    - my_date "2023-04-01"^^xsd:date
```

In this case, even without describing the process of attaching a language tag or data type as in the convert.yaml below,
the generated RDF will have the language tag or data type attached according to the object's example value in model.yaml.
convert.yaml (a pattern omitting the process of attaching a language tag or data type)
```yaml
- MySubject:
  - source("/path/to/csv_file.csv")
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - my_label: csv("label")
    - my_date: csv("date")
```

#### Determining whether an RDF property value is a URI or a literal
Whether the RDF property value generated according to the settings in convert.yaml becomes a URI or a literal is determined by
the example value of the object in model.yaml.

For example, consider the following model.yaml and convert.yaml.
model.yaml
```yaml
- MySubject <http://example.org/my_subject/1>:
  - rdfs:seeAlso:
    - uniprot: <http://identifiers.org/uniprot/Q9NQ94>
```

convert.yaml
```yaml
- MySubject:
  - source("/path/to/csv_file.csv")
  - subject:
    - csv("id_column")
    - prepend("http://example.org/my_subject/")
  - objects:
    - uniprot:
      - csv("uniprot_id")
      - prepend("http://identifiers.org/uniprot/")
```

In the model.yaml above, since the example value of the object `uniprot` is in RDF URI format,
the `uniprot` property value of the RDF triple generated according to convert.yaml will also be a URI.

### Using variables
In convert.yaml, you can set a value into a variable and reference it elsewhere.
To set a value into a variable, write the variable name as the key, and describe the rule for generating the variable's value in the value part corresponding to that key.

```yaml
- subject_name:
  - source("/path/to/file.csv")
  - $var1: generation_process_for_variable_$var1
  - subject:
    # ... subject generation rule
  - objects:
    - $var2:
      - generation_process2-1_for_variable_$var2
      - generation_process2-2_for_variable_$var2
    - object_name:
      - object_process1
      - object_process2
    # ...
```

As above, when a key starts with `$`, that key name is treated as a variable that can be used within convert.yaml.
The result of running the generation process corresponding to a key that starts with `$` is set as the value of the variable, and
the value of the variable can be referenced (used) from another place within convert.yaml.

For example, in the convert.yaml above, the value set into `$var2` can be referenced (used) in the generation-process part elsewhere in convert.yaml.
Specifically, there are two ways to reference (use) the value of a variable:
1. Specify a string with the variable name embedded in the generation-process part.<br/>⇒ For example, if "foo/$var2" is specified in the generation-process part and the value of `$var2` is `my_val`, then the value of `$var2` is expanded, and the result of the generation process becomes "foo/my_val".
2. Give the variable name as the argument of the generation process.<br/>⇒ The process is executed with the value of the variable name as the argument.

Below is an example of using variables.

TSV file (`person.tsv`)

| person_id | first_name | last_name | lang |
|-----------|------------|-----------|------|
| 1         | 一郎       | 鈴木      | ja   |
| 1         | Ichiro     | SUZUKI    | en   |

model.yaml
```yaml
- Person <http://example.org/ontology/person/1>:
  - a: foaf:Person
  - dct:identifier:
    - person_id: 1
  - foaf:name:
    - name: YAMADA Taro
```

convert.yaml
```yaml
- Person:
  - source("/path/to/person.tsv")
  - $id: tsv("person_id")
  - subject:
    - "http://example.org/ontology/person/$id"
  - objects:
    - person_id: $id
    - name:
      - $first_name: tsv("first_name")
      - $last_name: tsv("last_name")
      - $lang: tsv("lang")
      - "$last_name $first_name" # example of embedding variables in a string
      - lang($lang) # example of giving a variable as an argument to a process
```

The resource URI and property values are generated as follows.
1. Generation of the resource URI of the subject `Person`
   1. Let the path of the source TSV file be /path/to/person.tsv.
   2. Get the value of the `person_id` column of the TSV file, and set it into the variable `$id`.
   3. Set the resource value of `Person` to "http://example.org/ontology/person/$id".<br />⇒ Since the value of `$id` is set to 1, `$id` is expanded to 1, giving "http://example.org/ontology/person/1".
2. Generation of the property value of the object `person_id`<br />⇒ Since `$id` is 1, the property value of `person_id` becomes 1.
3. Generation of the property value of the object `name`
   1. Set the value of the TSV file's first_name column into the variable `$first_name`.
   2. Set the value of the TSV file's last_name column into the variable `$last_name`.
   3. Set the value of the TSV file's lang column into the variable `$lang`.
   4. Set the property value of `name` to "$last_name $first_name".<br />⇒ The values of `$last_name` and `$first_name` are expanded, giving "鈴木 一郎".
   5. Since the value of `$lang` is "ja", the language tag "ja" is set on the property value of `name`, giving "鈴木 一郎"@ja.

As a result of the above, the following RDF is generated.
```
@prefix dct: <http://purl.org/dc/terms/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<http://example.org/ontology/person/1> a foaf:Person;
  dct:identifier 1;
  foaf:name "鈴木 一郎"@ja,
    "SUZUKI Ichiro"@en .
```

## stanza.yaml

This describes the information needed for the metadata.json file used when generating a TogoStanza.

```yaml
stanza_name:
  output_dir: /path/to/output/dir     # output directory name (TODO: should this be freely changeable from the command line instead of here?)
  label: "the name of the stanza"
  definition: "the description of the stanza"
  sparql: pair_stanza                 # the name of the corresponding SPARQL query defined in sparql.yaml
  parameters:
    variable_name:
      example: default_value
      description: description
      required: true                  # whether the parameter is optional (true/false)
```

## description.yaml

Each dataset directory under `config/` may contain a `description.yaml` file that holds the dataset's display name and description.

```yaml
dataset:
  name: dataset name
  description: a brief description of the dataset
variables:
  SubjectName: description of the subject
  attribute_name: description of the attribute
```

This file consists of the following top-level keys.

* `dataset`: a mapping holding the dataset's metadata
* `dataset.name`: a string representing the dataset's display name
* `dataset.description`: a string representing a brief description of the dataset
* `variables`: an optional mapping from a subject name or attribute name appearing in model.yaml to its description

Only add a description under `variables` when the variable name alone does not sufficiently convey its meaning.
