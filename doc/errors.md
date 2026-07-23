# List of Error Messages

## Duplicate subject name (subject name) in model.yaml file.
The same subject name is set more than once in model.yaml.
Solution: Make the subject name unique within model.yaml.

## Duplicate variable name (object name) in model.yaml file.
The same object name is set more than once in model.yaml.
Solution: Make the object name unique within model.yaml.

## Invalid object name (object name) in model.yaml file. Only lowercase letters, numbers and underscores can be used in object name.
The object name does not satisfy the RDF-config specification.
Solution: Use snake_case for the object name, and use only lowercase letters, numbers, and underscores for the characters in the object name.

## Invalid subject name (subject name) in model.yaml file. Subject name must start with a capital letter and only alphanumeric characters can be used in subject name.
The subject name does not satisfy the RDF-config specification.
Solution: Use CamelCase for the subject name, and use only alphabetic characters for the subject name.

## It seems that the predicate and object settings in subject (subject name) are incorrect in the model.yaml file.
The predicate/object settings under the subject may not satisfy the RDF-config specification.
Solution: Check that the predicate and object settings conform to the RDF-config specification. Specifically, check the following:
- Whether the predicates and objects are set as a YAML array.
- Whether the indentation of the predicate or object is off. For example, check whether the predicate and object end up at the same indentation level.

## Predicate (predicate URI) has no RDF object setting.
No object is set for the predicate.
Solution: Check the following:
- Whether the predicate and object have the same indentation level in YAML. If the predicate and object settings end up at the same indentation level, RDF-config interprets the object part as another predicate and judges that no object has been set.

## Predicate (predicate URI) is not valid URI.
The predicate is not a URI.
Solution: Set the predicate to a valid URI format (a format like `prefix:local_part` or `<http://...>`).

## Prefix (namespace prefix) used in predicate (predicate URI) but not defined in prefix.yaml file.
The namespace prefix used in the predicate's URI is not set in prefix.yaml.
Solution: Set the namespace prefix and its corresponding URI in prefix.yaml.

## Prefix (namespace prefix) used in rdf:type (rdf:type URI) but not defined in prefix.yaml file.
The namespace prefix used in the rdf:type URI is not set in prefix.yaml.
Solution: Set the namespace prefix and its corresponding URI in prefix.yaml.

## Prefix (namespace prefix) used in subject (subject name), value (subject example) but not defined in prefix.yaml file.
The namespace prefix used in the subject's sample value is not set in prefix.yaml.
Solution: Set the namespace prefix and its corresponding URI in prefix.yaml.


## RDF object data (predicate is 'predicate URI') in model.yaml is not an array. Please specify the RDF object data as an array.
The object setting under the predicate is not an array.
Solution: Set the object as an array. (Per the RDF-config specification, objects must be specified as an array.)

## rdf:type (rdf:type URI) is not valid URI.
The value of rdf:type is not a URI.
Solution: Set the value of rdf:type to a valid URI format (a format like `prefix:local_part` or `<http://...>`).

## Subject (subject name), value (subject sample value) is not valid URI.
The subject's sample value is not a URI.
Solution: Set the subject's sample value to a valid URI format (a format like `prefix:local_part` or `<http://...>`).


# List of Warning Messages

## Multiple object names (object name) are set in the same property path (property path)
In the SPARQL generated based on model.yaml, there are multiple objects that resolve to the same property path.
In this case, the generated SPARQL assumes that the object name has the same value at every occurrence, so you may need to manually adjust the SPARQL variable names as needed to get the intended SPARQL.

## Subject (subject name) has no rdf:type.
No rdf:type is set for the subject. It is recommended to set rdf:type for the subject.

## Variable name (variable name) is set in sparql.yaml file, but not in model.yaml file.
A subject name or object name set in the `variables` of sparql.yaml is not defined in model.yaml. During SPARQL generation, variables that are not defined in model.yaml are ignored.
