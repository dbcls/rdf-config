export CONFIG=../../config/togovar

#bundle exec rdf-config --config $CONFIG --senbero
#bundle exec rdf-config --config $CONFIG --schema > schema.svg

#
# convert LD data
bundle exec rdf-config --config $CONFIG --format jsonld --convert ./PASS.autosome_PAR_ploidy_2.biallelic.chr22.tsv | jq

#
# convert TogoVar-MoG+ data
#bundle exec rdf-config --config $CONFIG --format jsonld --convert ./togovar_mogplus.tsv | jq
