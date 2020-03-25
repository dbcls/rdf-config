# RDF config (senbero)

![](assets/senbero-logo.png)

## TODO

* design
  * provides spec for validation of data type & cardinality to generate ShEx
* implement
  * support multiple models to be loaded in combination at once
* test

## GOAL

* DONE: capture the RDF data strucuture in ease
* DONE: generate SPARQL queries
* generate SPARQLet for SPARQList
* generate Grasp config file
* DONE: generate schema chart
* DONE: generate TogoStanza
* generate ShEx and validate RDF data

## SPECIFICATION

* [Japanese version](./doc/spec_ja.md)
* English version (under development)

## USAGE

### Installation

* Pre-requirements:
  * To generate Ruby version of TogoStanza, install [TogoStanza gem](https://github.com/togostanza/togostanza-gem) by running `gem install togostanza`
  * To generate JavaScript version of TogoStanza, install [ts](https://github.com/togostanza/ts/releases) command by downloading the latest release for your environment (e.g., ts_0.0.19_darwin_amd64.zip for macOS)

```
% git clone https://github.com/dbcls/rdf-config.git

% cd rdf-config

% export PATH="./bin:$PATH"
% export RUBYLIB="./lib" 
```

* TODO:
  * Installer will be provided soon!

### Generate schema ascii art

```
% rdf-config --config config/refex --senbero
RefExEntry (refexo:RefExEntry)
    |-- refexo:exValue
    |       `-- ex_value ("Ex value")
    |-- dct:identifier
    |       `-- refex_id ("RFX0016539731")
    |-- rdfs:seeAlso
    |       `-- see_also ("<http://identifiers.org/affy.probeset/224348_s_at>")
    `-- refexo:refexSample
            `-- RefExSample ("<http://refex.dbcls.jp/sample/RES00000884>")
RefExSample (refexo:RefExSample)
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
```
			
### Generate schema diagram

```
% rdf-config --config config/refex --schema > refex.svg
```

![RefEx schema](./doc/figure/refex.svg)

### Generate SPARQL query

```
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

### Generate TogoStanza

JavaScript version

```
% rdf-config --config config/hint --stanza_rb hint_pair_stanza
Stanza template has been generated successfully.
To view the stanza, run (cd stanza/javascript; ts server) and open http://localhost:8080/
```

Ruby version (it may take a while for the first time to install dependencies)

```
% rdf-config --config config/hint --stanza_rb hint_pair_stanza
Stanza template has been generated successfully.
To view the stanza, run (cd stanza/ruby; bundle exec rackup) and open http://localhost:9292/
```

## Authors

* Toshiaki Katayama (DBCLS)
* Tatsuya Nishizawa (IMSBIO)

## License

* MIT License


