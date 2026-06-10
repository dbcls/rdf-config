# Validation of configuration files
In RDF-config, in order to check the validity of the configuration file, when executing the rdf-config command, perform the following validation.

## Error check: In the following case, an error occurs
- **Does the subject name meet the RDF-config specification?**  
The subject name is CamelCase, and only English (capital letters and lowercase letters) can be used. If the subject name does not meet this condition, an error occurs.

- **Whether the sample value of the subject is a URI**  
If the sample value of the subject is not considered as a URI (`prefix:local_part` or `<http://...>`), it will be an error.

- **Whether the namespace prefix of the sample value of the subject is set to prefix.yaml**  
If the namespace prefix of the sample value (URI) of the subject is not set to prefix.yaml, an error occurs.

- **Whether rdf:type is a URI**  
If rdf:type values cannot be considered as URIs (`prefix:local_part` or `<http://...>`), it will be an error.

- **Whether the namespace prefix of rdf:type is set to prefix.yaml**  
If the namespace prefix of the rdf:type value (URI) is not set to prefix.yaml, an error occurs.

- **Whether the predicate is a URI**  
If the predicate is not considered as a URI (`prefix:local_part` or `<http://...>`), it will be an error.

- **Whether the namespace prefix of the predicate is set to prefix.yaml**  
An error occurs if the namespace prefix of the predicate (URI) is not set to prefix.yaml.

- **Does the object name meet the RDF-config specification?**  
The object name is snake_case, and only lowercase letters, numbers, and underscores are available. If the object name does not meet this condition, an error occurs.

- **Whether the subject name and the object name are unique in model.yaml**  
If the same subject name and object name appear multiple times in model.yaml, an error occurs.

- **Whether the predicate and the object setting method meets the RDF-config specification**  
As a specification of RDF-config, model.yaml is to be set in a nested array (to store the order) in the following structure. If model.yaml does not meet this condition, an error occurs.
```
- Subject subject_example1 subject_example2:
  - predicate:
    - object_name1: object_example1
  - predicate:
    - object_name2: object_example2
    - object_name3: object_example3
    - object_name4: object_example4
  - predicate:
    - []: # Blank node
      - predicate:
        - object_name: object_example
    - []:
      - predicate:
        - []: # Nested blank nodes
          - predicate:
            - object_name: object_example
```

As an example of an error, the following can be considered.
- The predicate and object are not set in the YAML array.
- The indentation of the object is out of place (For example, the predicate and the object are at the same indentation level).

## Warning check: In the following cases, it will be warning
- **Whether rdf: type is set to the subject**  
If rdf:type is not set in the subject, it is a warning.  
It is recommended to set rdf:type for the subject.

- **Whether there are multiple objects with the same property path**  
In SPARQL generated based on model.yaml, if there are multiple objects that are the same property path, it is a warning.  
In this case, a SPARQL is generated that assumes that the object has the same value at all occurrences, so it is necessary to manually modify the variable name to become the intended SPARQL as needed.

- **Whether the variable name set to the variables of sparql.yaml is in model.yaml**  
If the subject or object name set to the variables of sparql.yaml is not set in model.yaml, it is a warning.  
When SPARQL is generated, the subject and object names that are not set in model.yaml are ignored.
