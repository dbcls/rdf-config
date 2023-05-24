#!/bin/bash

echo '--- books (xml) ---'
bundle exec rdf-config --config work/convert/config/books --convert work/convert/books.xml

echo
echo '--- convert test (csv) ---'
bundle exec rdf-config --config work/convert/config/convert_test --convert work/convert/convert_test.csv

echo
echo '--- hgnc (tsv) ---'
bundle exec rdf-config --config work/convert/config/hgnc --convert work/convert/hgnc-subset.tsv

echo
echo '--- opdivo (xml) ---'
bundle exec rdf-config --config work/convert/config/opdivo --convert work/convert/opdivo-subset.xml

echo
echo '--- openopus (json) ---'
bundle exec rdf-config --config work/convert/config/openopus --convert work/convert/openopus-subset.json

echo
echo '--- openopus bnode (json) ---'
bundle exec rdf-config --config work/convert/config/openopus-bnode --convert work/convert/openopus-subset.json

echo
echo '--- openopus (xml) ---'
bundle exec rdf-config --config work/convert/config/openopus-xml --convert work/convert/openopus-subset.xml

echo
echo '--- openopus bnode (xml) ---'
bundle exec rdf-config --config work/convert/config/openopus-xml-bnode --convert work/convert/openopus-subset.xml

echo
echo '--- person (csv) ---'
bundle exec rdf-config --config work/convert/config/person-csv --convert work/convert/person.csv

echo
echo '--- person (json) ---'
bundle exec rdf-config --config work/convert/config/person-json --convert work/convert/person.json

echo
echo '--- person (xml) ---'
bundle exec rdf-config --config work/convert/config/person-xml --convert work/convert/person.xml
