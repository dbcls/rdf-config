# RDF-config specification

The configuration requires a small number of independant yaml files.


## endpoint.yaml

The SPARQL endpoint can be specified using the following notation.

```yaml
endpoint: http://example.org/sparql
```

Default endpoint must be specified by the `endpoint:` key.
If you want to specify multiple endpoints for the same data, use the following notation.
Each endpoint can contain graph names which are used in the FROM clause in the generated SPARQL query.

```yaml
endpoint:
  - http://example.org/sparql  # Primary SPARQL endpoint
  - graph:
    - http://example.org/graph/1
    - http://example.org/graph/2
    - http://example.org/graph/3

another_endpoint:
  - http://another.org/sparql  # Spare SPARQL endpoint
  - graph:
    - http://another.org/graph/A
    - http://another.org/graph/B
```

## prefix.yaml

The CURIE/QName prefix used in the RDF data model must be defined using the following notation.

```yaml
rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
rdfs: <http://www.w3.org/2000/01/rdf-schema#>
xsd: <http://www.w3.org/2001/XMLSchema#>
dc: <http://purl.org/dc/elements/1.1/>
dct: <http://purl.org/dc/terms/>
skos: <http://www.w3.org/2004/02/skos/core#>
```

## model.yaml

The RDF data model is described in the YAML format with the following structure containing nested arrays (to preserve order and allow for duplicate occurrences). Note that a mismatched indentation causes an error (don't mix spaces and a tab at the beginning of a line), and the subject, predicate, and object must end with `:` because each is a key of the hash.

```yaml
- Subject1 subject_example1 subject_example2:
  - predicate1:
    - object1: object_example1
  - predicate2:
    - object2: object_example2
    - object3: object_example3
    - object4: object_example4
  - predicate3:
    - []:  # blank node
      - predicate5:
        - object5: object_example5
    - []:
      - predicate5:
        - []:  # nested blank node
          - predicate6:
            - object6: object_example6
```

Subject examples and predicates are described by the URI (`<http://... >`) or CURIE/QName (`prefix:local_part`). Object examples can be URI/CURIE/QName or literal, and you may specify multiple objects if necessary. An blank node is described as [].

Since names of subjects and objects are used as variable name in the SPARQL query and the results, you must use unique names that are easy to understand. The subject name should be written in the form of CamelCase and the object name should be written in the form of snake_case. 

The most important point here is to assign appropriate variable names to represent the meaning of values. It is difficult to handle a table having a same column name in different columns (as it requires you to rename the columns by considering the meaning of each column before using it), so it is important to make each variable name "unique" and "easy to understand" in the model.yaml file.

### Subject

Define a subject name followed by example URIs (optional). Be sure to specify `rdf:type` (`a`) for the subject. Moreover, it is strongly recommended to include `rdfs:label` or `dct:identifier` for the subject.

In the case of the subject example is specified as a URI:
```yaml
- Entry <http://example.org/mydb/entry/1>:
  # for a subject having a single type
  - a: mydb:Entry
  # for a subject having multiple types
  - a: [ mydb:Entry, hoge:Fuga ]
  # for a subject having multiple types (verbose notation)
  - a:
    - mydb:Entry
    - hoge:Fuga
  # if you don't use "a" as the abbreviation of rdf:type, define rdf: in prefix.yaml
  - rdf:type:
    - mydb:Entry
    - hoge:Fuga
  - rdfs:label:
    - label: "1"
  - dct:identifier:
    - id: 1
```

In the case of the subject example is specified as a CURIE/QName:
```yaml
- Entry mydb:1:
  - a: mydb:Entry
 :
```

In the case of the subject is a blank node:
```yaml
- []:
  - a: mydb:Entry
 :
```

Multiple example URIs for a subject can be specified with a space delimited list next to the subject name. 

```yaml
- Entry mydb:1 mydb:2:
  - a: mydb:Entry
 :
```

### Predicate

Enumerate predicates hanging from the subject as an array of URIs (`<http://... >`) or CURIE/QName (`prefix:local_part`).

You can clarify the constraints on the number of occurrences of a predicate (cardinality) by adding the following symbol at the end of a predicate.

* None: No judgment (interpreted as assuming `{1}`, i.e. the corresponding value is `one')
* `? `: 0 or 1 (if the corresponding value is "missing" or "limited to one" -> it becomes an OPTIONAL clause)
* `*`: 0 or more (if the corresponding value is "no" or "more than one possible" -> it becomes an OPTIONAL clause)
* `+`: more than one (the corresponding value should be "there" and there is "more than one possible")
* `{n}`: n (if the corresponding value is limited to "n")
* `{n,m}`: n to m (if the corresponding value is limited to between "n" and "m")


This information is also used to make OPTIONAL clause in the generated SPARQL query and is also used by genrated ShEx for RDF validation and 

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

Since RDF data is based on the Open world assumption, we cannot guarantee that there is always one (not more than one) value corresponding to a predicate. So be careful that the distinction between `predicate` and `predicate+` and between `predicate?` and `predicate*` does not represented in the SPARQL query.

### Object

An object hanging from a predicate describes the object name and an example of the object. 
The object name is used as the name of a variable in SPARQL queries, so it should be unique and set in snake_case in the model.yaml file.

Example of objects is optional, but we strongly recommended to add it to make the schema diagram clearer. Because the YAML parser estimates the type of the value, you can write strings  (it doesn't matter for YAML in the case of without quote), numbers, dates, etc. as they are. Because URI is treated as strings in YAML, RDF-config specially interprets the strings enclosed in `<>` and CURIE/QName (whose prefix is defined in prefix.yaml) as URIs.

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

When the object refers to another RDF model, the subject name of the reference should be described as the object.
(TODO: Extend it to allow external references to commonly used data models such as FALDO.)

```yaml
- Subject my:subject:
  - my:refer:
    - other_subject: OtherSubject  # Subject names used as subjects in the same model.yaml
- OtherSubject my:other_subject:
  - a: my:OtherClass
```

If the object example is described in more than one line, the indented part is treated as a multi-line literal by using `|` in YAML notation. Note that if it is too long, it may not be displayed in the schema diagram or may be broken.

```yaml
- Subject my:subject:
  - my:predicate:
    - value: |
        long long line of
         example explanation
        in detail
```

The language tags (such as `"hoge"@en`) can be specified like as follows. 
(it will be an error for YAML without `"`)

```yaml
- Subject my:subject:
  - my:predicate:
    - name: '"hoge"@en'
```

For literal type specification by `^^` (e.g., `"123"^^xsd:string`), you can specify as follows.
(it will be an error for YAML without `"`)

```yaml
- Subject my:subject:
  - my:predicate:
    - myvalue: '"123"^^xsd:integer'
```

## schema.yaml

In case of drawing a schema only with the selected subset of Subjects and/or Objects, especially when the model.yaml became too complex, specify a name and variables of schemas in the following YAML format:

```yaml
schema_name1:
  description: A list of subjects and objects which will be drawn on the schema diagram.
  variables: [ Subject1, Subject2, object_name1, object_name2, object_name3 ]

schema_name2:
  description: A list of selected objects. Other objects will be ommitted from the schema diagram.
  variables: [ object_name1, object_name2, object_name3 ]

schema_name3:
  description: A list of selected subjects. All objects belong to the subjects will be drawn on the schema diagram.
  variables: [ Subject1, Subject2 ]

schema_name4:
  description: Specify a title of the schema only.
```

## sparql.yaml

A file that can configure multiple SPARQL queries. It is written in the following YAML format.

In RDF-config, it identifies the necessary property paths from the names of target objects and generates SPARQL queries automatically. So all you have to do is list the name of the variable that you want to get as a result in the variables.
When creating a query that takes a partial value as an argument, such as an ID or a name, specify in parameters the name of the variable to be set as a value and its default value.

```yaml
query_name:
  description: explanation about SPARQL query 
  variables: [ foo, bar, ... ]  # Enumerates the object names  (variable names) to be targeted for SELECT in SPARQL

query_with_parameters:
  description: explanation about SPAQRL query
  variables: [ foo, bar, ... ]  # Enumerates the object names  (variable names) to be targeted for SELECT in SPARQL
  parameters:
    object_name: default_value

query_with_options:
  description: explanation about SPAQRL query
  variables: [ foo, bar, ... ]  # Enumerates the object names  (variable names) to be targeted for SELECT in SPARQL
  options:
    distinct: true   # SELECT DISTINCT ...
    limit: 500       # set false to disable LIMIT clause
    offset: 200
    order_by:        # ORDER BY ?var1 DESC(?var2) ?var3
    - var1: asc      # ascending order
    - var2: desc     # descending order
    - var3           # asc by default (optional)
```

Note that, if a subject of the given variable appears as an nested object of multiple subjects, a generated SPARQL query assumes the value of the variable is same in all occurences, therefore, you might want to manually rename variable names in the SPARQL query depending on your intention.

## stanza.yaml

A file describing information for the metadata.json file, which is necessary to generate TogoStanza.

```yaml
Stanza name:
  output_dir: /path/to/output/dir     # Output directory name (TODO: should I be able to change it on the command line instead of writing it here?)
  label: "Stanza name"
  definition: "Explanation of stanza"
  sparql: pair_stanza                 # The name of the corresponding SPARQL query defined in sparql.yaml
  parameters:
    variable name:
      example: default value
      description: explanation
      required: true                  # Whether it is an optional parameter or not (true/false)
```


