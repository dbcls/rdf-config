# RDF config (senbero)

![](assets/senbero-logo.png)

## TODO

* design
  * provides spec for validation of data type & cardinality to generate ShEx
* implement
* test

## GOAL

* capture the RDF data strucuture in ease
* generate SPARQL queries
* generate schema chart
* generate TogoStanza
* generate dataset for machine learning
  * set of APIs for SPARQList
  * bulk download
  * data frame

## USAGE

```
% ruby senbero.rb config/refex.yaml                                          
refexo:RefExEntry (A RefEx entry)
    |-- refexo:refexSample
    |       `-- refexo:RefExSample (A RefEx sample)
    |-- refexo:exValue
    |       `-- refexo:TPM (An expression value)
    |-- dct:identifier
    |       `-- xsd:string (An identifier)
    |-- rdfs:seeAlso
    |       `-- xxxx:NCBIGeneID or xxxx:AffymetrixID or xsd:string (ID) or a Resource URI (foobar)
refexo:RefExSample (A RefEx sample)
    |-- dct:identifier
    |       `-- xsd:string (An identifier)
    |-- refexo:organism
    |       `-- Resource (A taxonomy ID)
    |-- refexo:refexTissueClass10
    |       `-- refexo:AnatomicalClassification10 ()
    |-- refexo:refexTissueClass40
    |       `-- refexo:AnatomicalClassification40 ()
    |-- refexo:sex
    |       `-- xsd:string (Male/Female)
    |-- refexo:refexAlphabeticalUniqOrder
    |       `-- xsd:string || xsd:integer (A description || A number)
    |-- refexo:refexRefinedDescription
    |       `-- xsd:string (A description)
    |-- refexo:refexSampleCategory
    |       `-- xsd:string (A category)
    |-- refexo:sampleReference
    |       `-- blank ()
    |-- refexo:sampleReference/refexo:belongsToCellType
    |       `-- UBERON (A UBERON class)
    |-- refexo:sampleReference/refexo:belongsToDisease
    |       `-- CO (A Cell Ontology)
    |-- refexo:sampleReference/refexo:belongsToDevelopmentSite
    |       `-- UBERON (A UBERON class)
    |-- refexo:sampleReference/refexo:sample
    |       `-- xsd:string (A BioSample entry)

% ruby senbero.rb --stanza config/refex.yaml
# RefExStanza https://integbio.jp/rdf/sparql

PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX dct: <http://purl.org/dc/terms/>
PREFIX refexo: <http://purl.jp/bio/01/refexo#>

SELECT *
FROM <http://refex.dbcls.jp/rdf/fantom5>
WHERE {
  ?s refexo:RefExEntry#dct:identifier ?id .
  ?s refexo:RefExEntry#refexo:exValue ?value .
  ?s refexo:RefExEntry#rdfs:seeAlso ?link .
  ?s refexo:RefExEntry#refexo:refexSample/refexo:RefExSample#dct:identifier ?sample .
  ?s refexo:RefExEntry#refexo:refexSample/refexo:RefExSample#refexo:organism ?organism .
}
```

