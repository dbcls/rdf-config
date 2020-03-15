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
% rdf-config --config config/refex --senbero
RefEx_Entry (refexo:RefExEntry)
    |-- refexo:exValue
    |       `-- ex_value ("Ex value")
    |-- dct:identifier
    |       `-- refex_id ("RFX0016539731")
    |-- rdfs:seeAlso
    |       `-- see_also ("<http://identifiers.org/affy.probeset/224348_s_at>")
    `-- refexo:refexSample
            `-- RefEx_Sample ("<http://refex.dbcls.jp/sample/RES00000884>")
RefEx_Sample (refexo:RefExSample)
    |-- dct:identifier
    |       `-- sample_id ("RES00000100")
    |-- refexo:organism
    |       `-- taxonomy ("<http://identifiers.org/taxonomy/9606>")
    |-- refexo:refexTissueClass10
    |       `-- class10 ("refexo:v04_10")
    |-- refexo:refexTissueClass40
    |       `-- class40 ("refexo:v20_4")
    |-- refexo:sex
    |       `-- sex ("obo:PATO_0000383")
    |-- refexo:refexAlphabeticalUniqOrder
    |       `-- unique_order (210)
    |-- refexo:refexRefinedDescription
    |       `-- ref_description ("uterus, adult")
    |-- refexo:refexSampleCategory
    |       `-- sample_category ("developmental")
    |-- refexo:sampleReference / refexo:belongsToCellType
    |       `-- cell_type ("obo:CL_0000003")
    |-- refexo:sampleReference / refexo:belongsToDisease
    |       `-- disease ("obo:DOID_0050686")
    |-- refexo:sampleReference / refexo:belongsToDevelopmentSite
    |       `-- dev_site ("obo:CL_0000134")
    `-- refexo:sampleReference / refexo:sample
            `-- refexo_sample ("<http://fantom.gsc.riken.jp/5/sstar/FF:10828-111C9>")

% rdf-config --config config/nbrc --senbero
Culture (mccv:MCCV_000001)
    |-- dct:identifier
    |       `-- nbrc_id ("NBRC_00012843")
    |-- mccv:MCCV_000010
    |       `-- label ("NBRC 12843")
    |-- mccv:MCCV_000038
    |       `-- clade ("mccv:MCCV_000040")
    |-- skos:prefLabel
    |       `-- name ("Kitasatospora aureofaciens")
    |-- skos:altLabel
    |       `-- alias ("Streptomyces aureofaciens")
    |-- mccv:MCCV_000065
    |       `-- taxid ("taxonomy:1894")
    |-- mccv:MCCV_000046
    |       `-- approved (1)
    |-- mccv:MCCV_000017
    |       `-- type_strain (1)
    |-- sio:SIO_000216 / sio:SIO_000221
    |       `-- unit ("obo:UO_0000027")
    |-- sio:SIO_000216 / sio:SIO_000300
    |       `-- value (28)
    |-- mccv:MCCV_000073 / mccv:MCCV_000018
    |       `-- growth_medium ("<http://purl.jp/bio/103/nite/medium/NBRC_M000227>")
    |-- mccv:MCCV_000073 / mccv:MCCV_000019
    |       `-- rehydration_fluid ("<http://purl.jp/bio/103/nite/medium/NBRC_M000707>")
    |-- mccv:MCCV_000024 / mccv:MCCV_000025
    |       `-- xref ("<https://www.dsmz.de/catalogues/details/culture/DSM-40127.html>")
    |-- mccv:MCCV_000024 / dct:identifier
    |       `-- id1 ("DSM 40127")
    |-- mccv:MCCV_000027
    |       `-- history ("IFO 12843 <- SAJ <- OWU (ISP 5127) <- Lederle Labs. (E. Backus, A-377)")
    |-- mccv:MCCV_000028 / mccv:MCCV_000072 / sio:SIO_000008
    |       |-- attribute ("meo:MEO_0000007")
    |       `-- gazetteer ("obo:GAZ_00600942")
    |-- mccv:MCCV_000028 / mccv:MCCV_000072 / mccv:MCCV_000030
    |       `-- habitat ("Soil, USA")
    |-- mccv:MCCV_000028 / mccv:MCCV_000072 / rdfs:label
    |       `-- location ("USA")
    |-- mccv:MCCV_000028 / mccv:MCCV_000072 / sio:SIO_000008
    |       |-- attribute ("meo:MEO_0000007")
    |       `-- gazetteer ("obo:GAZ_00600942")
    |-- dct:references
    |       `-- reference ("pubmed:14657141")
    |-- mccv:MCCV_000033
    |       `-- application ("Chlortetracycline\n(aureomycin);production\n")
    `-- mccv:MCCV_000076
            `-- culture_collection ("<http://www.wfcc.info/ccinfo/collection/by_id/825>")


% rdf-config --config config/nbrc --sparql                                                       
# https://integbio.jp/rdf/sparql

PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX dct: <http://purl.org/dc/terms/>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
PREFIX pubmed: <http://rdf.ncbi.nlm.nih.gov/pubmed/>
PREFIX taxonomy: <http://identifiers.org/taxonomy/>
PREFIX sio: <http://semanticscience.org/resource/>
PREFIX obo: <http://purl.obolibrary.org/obo/>
PREFIX mccv: <http://purl.jp/bio/10/mccv#>
PREFIX meo: <http://purl.jp/bio/11/meo/>
PREFIX mpo: <http://purl.jp/bio/10/mpo/>
PREFIX nbrc: <http://purl.jp/bio/103/nite/cultures/>

SELECT ?s ?nbrc_id ?clade ?name ?alias ?taxid ?attribute ?habitat
WHERE {
  ?s a mccv:MCCV_000001 .
  ?s dct:identifier ?nbrc_id .
  ?s mccv:MCCV_000038 ?clade .
  ?s skos:prefLabel ?name .
  ?s skos:altLabel ?alias .
  ?s mccv:MCCV_000065 ?taxid .
  ?s mccv:MCCV_000028 / mccv:MCCV_000072 / sio:SIO_000008 ?attribute .
  ?s mccv:MCCV_000028 / mccv:MCCV_000072 / mccv:MCCV_000030 ?habitat .
}
LIMIT 100
```

