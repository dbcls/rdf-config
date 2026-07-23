# Validation of configuration files
In RDF-config, in order to check the validity of the configuration files, the following validations are performed when the rdf-config command is executed.

## Error checks: the following cases result in an error
- **Whether the subject name satisfies the RDF-config specification**  
The subject name must be in CamelCase, and only alphabetic characters (uppercase and lowercase) may be used. If the subject name does not meet this condition, it results in an error.

- **Whether the subject's sample value is a URI**  
If the subject's sample value cannot be regarded as a URI (i.e., it is not in a format such as `prefix:local_part` or `<http://...>`), it results in an error.

- **Whether the namespace prefix of the subject's sample value is set in prefix.yaml**  
If the namespace prefix of the subject's sample value (URI) is not set in prefix.yaml, it results in an error.

- **Whether rdf:type is a URI**  
If the value of rdf:type cannot be regarded as a URI (i.e., it is not in a format such as `prefix:local_part` or `<http://...>`), it results in an error.

- **Whether the namespace prefix of rdf:type is set in prefix.yaml**  
If the namespace prefix of the value (URI) of rdf:type is not set in prefix.yaml, it results in an error.

- **Whether the predicate is a URI**  
If the predicate cannot be regarded as a URI (i.e., it is not in a format such as `prefix:local_part` or `<http://...>`), it results in an error.

- **Whether the namespace prefix of the predicate is set in prefix.yaml**  
If the namespace prefix of the predicate (URI) is not set in prefix.yaml, it results in an error.

- **Whether the object name satisfies the RDF-config specification**  
The object name must be in snake_case, and only lowercase letters, numbers, and underscores may be used. If the object name does not meet this condition, it results in an error.

- **Whether the subject name and object name are unique within model.yaml**  
If the same subject name or object name appears more than once within model.yaml, it results in an error.

- **Whether the way the predicate and object are set satisfies the RDF-config specification**  
Per the RDF-config specification, model.yaml must be set as nested arrays (in order to preserve order) with the following structure. If model.yaml does not meet this condition, it results in an error.
```
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

The following are conceivable examples of what causes an error.
- The predicate or object is not set as a YAML array.
- The object's indentation is off (the predicate and object end up at the same indentation level).


## Warning checks: the following cases result in a warning
- **Whether rdf:type is set on the subject**  
If rdf:type is not set on the subject, it results in a warning.  
It is recommended to set rdf:type on the subject.

- **Whether there are multiple objects that share the same property path**  
In the SPARQL generated based on model.yaml, if there are multiple objects that resolve to the same property path, it results in a warning.  
In this case, the generated SPARQL assumes that the object has the same value at every occurrence, so you may need to manually adjust the variable names as needed to get the intended SPARQL.

- **Whether a variable name set in the `variables` of sparql.yaml exists in model.yaml**  
If a subject name or object name set in the `variables` of sparql.yaml is not defined in model.yaml, it results in a warning.  
During SPARQL generation, subject names and object names that are not defined in model.yaml are ignored.
