#!/bin/bash

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

curl -sLO https://civicdb.org/downloads/nightly/nightly-FeatureSummaries.tsv
curl -sLO https://civicdb.org/downloads/nightly/nightly-VariantSummaries.tsv
curl -sLO https://civicdb.org/downloads/nightly/nightly-AcceptedClinicalEvidenceSummaries.tsv

duckdb civic.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE features AS SELECT * FROM read_csv_auto('nightly-FeatureSummaries.tsv', delim='\t', header=True);"

duckdb civic.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE variants AS SELECT * FROM read_csv_auto('nightly-VariantSummaries.tsv', delim='\t', header=True);"

duckdb civic.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE clinical_evidences AS SELECT * FROM read_csv_auto('nightly-AcceptedClinicalEvidenceSummaries.tsv', delim='\t', header=True);"

duckdb civic.duckdb \
  'CREATE VIEW feature_variants AS
   SELECT
     "features"."feature_id" AS "features_feature_id",
     "features"."feature_civic_url" AS "features_feature_civic_url",
     "features"."feature_type" AS "features_feature_type",
     "features"."name" AS "features_name",
     "features"."feature_aliases" AS "features_feature_aliases",
     "features"."description" AS "features_description",
     "features"."last_review_date" AS "features_last_review_date",
     "features"."is_flagged" AS "features_is_flagged",
     "features"."entrez_id" AS "features_entrez_id",
     "features"."ncit_id" AS "features_ncit_id",
     "features"."five_prime_partner_status" AS "features_five_prime_partner_status",
     "features"."three_prime_partner_status" AS "features_three_prime_partner_status",
     "features"."five_prime_gene_id" AS "features_five_prime_gene_id",
     "features"."five_prime_gene_name" AS "features_five_prime_gene_name",
     "features"."five_prime_gene_entrez_id" AS "features_five_prime_gene_entrez_id",
     "features"."three_prime_gene_id" AS "features_three_prime_gene_id",
     "features"."three_prime_gene_name" AS "features_three_prime_gene_name",
     "features"."three_prime_gene_entrez_id" AS "features_three_prime_gene_entrez_id",
     "variants"."variant_id" AS "variants_variant_id",
     "variants"."variant_civic_url" AS "variants_variant_civic_url",
     "variants"."feature_type" AS "variants_feature_type",
     "variants"."feature_id" AS "variants_feature_id",
     "variants"."feature_name" AS "variants_feature_name",
     "variants"."feature_civic_url" AS "variants_feature_civic_url",
     "variants"."variant" AS "variants_variant",
     "variants"."variant_aliases" AS "variants_variant_aliases",
     "variants"."is_flagged" AS "variants_is_flagged",
     "variants"."variant_groups" AS "variants_variant_groups",
     "variants"."variant_types" AS "variants_variant_types",
     "variants"."single_variant_molecular_profile_id" AS "variants_single_variant_molecular_profile_id",
     "variants"."last_review_date" AS "variants_last_review_date",
     "variants"."gene" AS "variants_gene",
     "variants"."entrez_id" AS "variants_entrez_id",
     "variants"."chromosome" AS "variants_chromosome",
     "variants"."start" AS "variants_start",
     "variants"."stop" AS "variants_stop",
     "variants"."reference_bases" AS "variants_reference_bases",
     "variants"."variant_bases" AS "variants_variant_bases",
     "variants"."representative_transcript" AS "variants_representative_transcript",
     "variants"."ensembl_version" AS "variants_ensembl_version",
     "variants"."reference_build" AS "variants_reference_build",
     "variants"."hgvs_descriptions" AS "variants_hgvs_descriptions",
     "variants"."allele_registry_id" AS "variants_allele_registry_id",
     "variants"."clinvar_ids" AS "variants_clinvar_ids",
     "variants"."ncit_id" AS "variants_ncit_id",
     "variants"."5_prime_partner_status" AS "variants_5_prime_partner_status",
     "variants"."5_prime_partner" AS "variants_5_prime_partner",
     "variants"."3_prime_partner_status" AS "variants_3_prime_partner_status",
     "variants"."3_prime_partner" AS "variants_3_prime_partner",
     "variants"."vicc_compliant_name" AS "variants_vicc_compliant_name",
     "variants"."5_prime_transcript" AS "variants_5_prime_transcript",
     "variants"."5_prime_end_exon" AS "variants_5_prime_end_exon",
     "variants"."5_prime_exon_offset" AS "variants_5_prime_exon_offset",
     "variants"."5_prime_exon_offset_direction" AS "variants_5_prime_exon_offset_direction",
     "variants"."3_prime_transcript" AS "variants_3_prime_transcript",
     "variants"."3_prime_start_exon" AS "variants_3_prime_start_exon",
     "variants"."3_prime_exon_offset" AS "variants_3_prime_exon_offset",
     "variants"."3_prime_exon_offset_direction" AS "variants_3_prime_exon_offset_direction"
   FROM
     features
   INNER JOIN
     variants
   ON
     features.feature_id = variants.feature_id;'
