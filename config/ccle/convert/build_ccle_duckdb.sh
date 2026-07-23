#!/bin/bash

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

./convert_ccle_gct_to_tsv.rb CCLE_DepMap_18q3_RNAseq_RPKM_20180718.gct

duckdb ccle.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE cell_lines_annotations AS SELECT * FROM read_csv_auto('Cell_lines_annotations_20181226.txt', delim='\t', header=True);"

duckdb ccle.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE depmap_mafs AS SELECT * FROM read_csv_auto('CCLE_DepMap_18q3_maf_20180718.txt', delim='\t', header=True);"

duckdb ccle.duckdb \
  "SET enable_progress_bar = false;
   CREATE TABLE gene_expressions AS SELECT * FROM read_csv_auto('gene_expressions.tsv', delim='\t', header=True);"

duckdb ccle.duckdb \
  "CREATE VIEW ensembl_genes AS
   SELECT DISTINCT
     ensembl_gene_id,
     gene_name
   FROM
     gene_expressions;"

duckdb ccle.duckdb \
  'CREATE VIEW ccle_gene_expressions AS
   SELECT
     cell_lines_annotations."CCLE_ID" AS ccle_CCLE_ID,
     cell_lines_annotations."depMapID" AS ccle_depMapID,
     cell_lines_annotations."Name" AS ccle_Name,
     cell_lines_annotations."Pathology" AS ccle_Pathology,
     cell_lines_annotations."Site_Primary" AS ccle_Site_Primary,
     cell_lines_annotations."Site_Subtype1" AS ccle_Site_Subtype1,
     cell_lines_annotations."Site_Subtype2" AS ccle_Site_Subtype2,
     cell_lines_annotations."Site_Subtype3" AS ccle_Site_Subtype3,
     cell_lines_annotations."Histology" AS ccle_Histology,
     cell_lines_annotations."Hist_Subtype1" AS ccle_Hist_Subtype1,
     cell_lines_annotations."Hist_Subtype2" AS ccle_Hist_Subtype2,
     cell_lines_annotations."Hist_Subtype3" AS ccle_Hist_Subtype3,
     cell_lines_annotations."Gender" AS ccle_Gender,
     cell_lines_annotations."Life_Stage" AS ccle_Life_Stage,
     cell_lines_annotations."Age" AS ccle_Age,
     cell_lines_annotations."Race" AS ccle_Race,
     cell_lines_annotations."Geo_Loc" AS ccle_Geo_Loc,
     cell_lines_annotations."inferred_ethnicity" AS ccle_inferred_ethnicity,
     cell_lines_annotations."Site_Of_Finding" AS ccle_Site_Of_Finding,
     cell_lines_annotations."Disease" AS ccle_Disease,
     cell_lines_annotations."Annotation_Source" AS ccle_Annotation_Source,
     cell_lines_annotations."Original.Source.of.Cell.Line" AS ccle_Original_Source_of_Cell_Line,
     cell_lines_annotations."Characteristics" AS ccle_Characteristics,
     cell_lines_annotations."Growth.Medium" AS ccle_Growth_Medium,
     cell_lines_annotations."Supplements" AS ccle_Supplements,
     cell_lines_annotations."Freezing.Medium" AS ccle_Freezing_Medium,
     cell_lines_annotations."Doubling.Time.from.Vendor" AS ccle_Doubling_Time_from_Vendor,
     cell_lines_annotations."Doubling.Time.Calculated.hrs" AS ccle_Doubling_Time_Calculated_hrs,
     cell_lines_annotations."type" AS ccle_type,
     cell_lines_annotations."type_refined" AS ccle_type_refined,
     cell_lines_annotations."PATHOLOGIST_ANNOTATION" AS ccle_PATHOLOGIST_ANNOTATION,
     cell_lines_annotations."mutRate" AS ccle_mutRate,
     cell_lines_annotations."tcga_code" AS ccle_tcga_code,
     gene_expressions.ensembl_gene_id AS gene_exp_ensembl_gene_id,
     gene_expressions.gene_name AS gene_exp_gene_name,
     gene_expressions.gene_expression AS gene_exp_gene_expression
   FROM
     cell_lines_annotations
   JOIN
     gene_expressions
   ON cell_lines_annotations."depMapID" = gene_expressions.depmap_id;'

duckdb ccle.duckdb \
  'CREATE VIEW ccle_depmap_mafs AS
   SELECT
     cell_lines_annotations."CCLE_ID" AS ccle_CCLE_ID,
     cell_lines_annotations."depMapID" AS ccle_depMapID,
     cell_lines_annotations."Name" AS ccle_Name,
     cell_lines_annotations."Pathology" AS ccle_Pathology,
     cell_lines_annotations."Site_Primary" AS ccle_Site_Primary,
     cell_lines_annotations."Site_Subtype1" AS ccle_Site_Subtype1,
     cell_lines_annotations."Site_Subtype2" AS ccle_Site_Subtype2,
     cell_lines_annotations."Site_Subtype3" AS ccle_Site_Subtype3,
     cell_lines_annotations."Histology" AS ccle_Histology,
     cell_lines_annotations."Hist_Subtype1" AS ccle_Hist_Subtype1,
     cell_lines_annotations."Hist_Subtype2" AS ccle_Hist_Subtype2,
     cell_lines_annotations."Hist_Subtype3" AS ccle_Hist_Subtype3,
     cell_lines_annotations."Gender" AS ccle_Gender,
     cell_lines_annotations."Life_Stage" AS ccle_Life_Stage,
     cell_lines_annotations."Age" AS ccle_Age,
     cell_lines_annotations."Race" AS ccle_Race,
     cell_lines_annotations."Geo_Loc" AS ccle_Geo_Loc,
     cell_lines_annotations."inferred_ethnicity" AS ccle_inferred_ethnicity,
     cell_lines_annotations."Site_Of_Finding" AS ccle_Site_Of_Finding,
     cell_lines_annotations."Disease" AS ccle_Disease,
     cell_lines_annotations."Annotation_Source" AS ccle_Annotation_Source,
     cell_lines_annotations."Original.Source.of.Cell.Line" AS ccle_Original_Source_of_Cell_Line,
     cell_lines_annotations."Characteristics" AS ccle_Characteristics,
     cell_lines_annotations."Growth.Medium" AS ccle_Growth_Medium,
     cell_lines_annotations."Supplements" AS ccle_Supplements,
     cell_lines_annotations."Freezing.Medium" AS ccle_Freezing_Medium,
     cell_lines_annotations."Doubling.Time.from.Vendor" AS ccle_Doubling_Time_from_Vendor,
     cell_lines_annotations."Doubling.Time.Calculated.hrs" AS ccle_Doubling_Time_Calculated_hrs,
     cell_lines_annotations."type" AS ccle_type,
     cell_lines_annotations."type_refined" AS ccle_type_refined,
     cell_lines_annotations."PATHOLOGIST_ANNOTATION" AS ccle_PATHOLOGIST_ANNOTATION,
     cell_lines_annotations."mutRate" AS ccle_mutRate,
     cell_lines_annotations."tcga_code" AS ccle_tcga_code,
     depmap_mafs."Hugo_Symbol" AS maf_Hugo_Symbol,
     depmap_mafs."Entrez_Gene_Id" AS maf_Entrez_Gene_Id,
     depmap_mafs."NCBI_Build" AS maf_NCBI_Build,
     depmap_mafs."Chromosome" AS maf_Chromosome,
     depmap_mafs."Start_position" AS maf_Start_position,
     depmap_mafs."End_position" AS maf_End_position,
     depmap_mafs."Strand" AS maf_Strand,
     depmap_mafs."Variant_Classification" AS maf_Variant_Classification,
     depmap_mafs."Variant_Type" AS maf_Variant_Type,
     depmap_mafs."Reference_Allele" AS maf_Reference_Allele,
     depmap_mafs."Tumor_Seq_Allele1" AS maf_Tumor_Seq_Allele1,
     depmap_mafs."dbSNP_RS" AS maf_dbSNP_RS,
     depmap_mafs."dbSNP_Val_Status" AS maf_dbSNP_Val_Status,
     depmap_mafs."Genome_Change" AS maf_Genome_Change,
     depmap_mafs."Annotation_Transcript" AS maf_Annotation_Transcript,
     depmap_mafs."Tumor_Sample_Barcode" AS maf_Tumor_Sample_Barcode,
     depmap_mafs."cDNA_Change" AS maf_cDNA_Change,
     depmap_mafs."Codon_Change" AS maf_Codon_Change,
     depmap_mafs."Protein_Change" AS maf_Protein_Change,
     depmap_mafs."isDeleterious" AS maf_isDeleterious,
     depmap_mafs."isTCGAhotspot" AS maf_isTCGAhotspot,
     depmap_mafs."TCGAhsCnt" AS maf_TCGAhsCnt,
     depmap_mafs."isCOSMIChotspot" AS maf_isCOSMIChotspot,
     depmap_mafs."COSMIChsCnt" AS maf_COSMIChsCnt,
     depmap_mafs."ExAC_AF" AS maf_ExAC_AF,
     depmap_mafs."WES_AC" AS maf_WES_AC,
     depmap_mafs."SangerWES_AC" AS maf_SangerWES_AC,
     depmap_mafs."SangerRecalibWES_AC" AS maf_SangerRecalibWES_AC,
     depmap_mafs."RNAseq_AC" AS maf_RNAseq_AC,
     depmap_mafs."HC_AC" AS maf_HC_AC,
     depmap_mafs."RD_AC" AS maf_RD_AC,
     depmap_mafs."WGS_AC" AS maf_WGS_AC,
     depmap_mafs."Broad_ID" AS maf_Broad_ID
   FROM
     cell_lines_annotations
   JOIN
     depmap_mafs
   ON cell_lines_annotations.CCLE_ID = depmap_mafs.Tumor_Sample_Barcode;'
