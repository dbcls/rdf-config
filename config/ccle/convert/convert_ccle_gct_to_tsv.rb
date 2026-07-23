#!/usr/bin/env ruby
# frozen_string_literal: true

# Converts a CCLE GCT expression matrix into a long-format TSV.
#
# Usage:
#   ruby convert_ccle_gct_to_tsv.rb [INPUT.gct [OUTPUT.tsv]]
#
# Example:
#   ruby convert_ccle_gct_to_tsv.rb \
#     CCLE_DepMap_18q3_RNAseq_RPKM_20180718.gct \
#     gene_expressions.tsv

BUFFER_LIMIT = 8 * 1024 * 1024 # 8 MiB

input_path = ARGV[0] || "CCLE_DepMap_18q3_RNAseq_RPKM_20180718.gct"

unless input_path
  warn "Usage: #{File.basename($PROGRAM_NAME)} INPUT.gct [OUTPUT.tsv]"
  exit 1
end

unless File.file?(input_path)
  warn "Input file not found: #{input_path}"
  exit 1
end

output_path = ARGV[1] || File.join(File.dirname(input_path), "gene_expressions.tsv")

# "22RV1_PROSTATE (ACH-000956)" is split into:
#   ccle_name = "22RV1_PROSTATE"
#   depmap_id = "ACH-000956"
def parse_sample_header(header)
  match = header.match(/\A(.+?)\s+\((ACH-\d+)\)\z/)

  if match
    [match[1], match[2]]
  else
    # Keep an unrecognized header rather than discarding the column.
    warn "Warning: could not extract a DepMap ID from sample header: #{header.inspect}"
    [header, ""]
  end
end

File.open(input_path, "rb") do |input|
  version_line = input.gets
  dimensions_line = input.gets
  header_line = input.gets

  unless version_line && dimensions_line && header_line
    warn "Invalid GCT file: the file must contain at least three header lines"
    exit 1
  end

  headers = header_line.chomp.split("\t", -1)

  if headers.length < 3
    warn "Invalid GCT header: no sample columns were found"
    exit 1
  end

  sample_columns = headers.drop(2).map { |header| parse_sample_header(header) }
  expected_column_count = headers.length

  File.open(output_path, "wb") do |output|
    output.write("ensembl_gene_id\tgene_name\tccle_name\tdepmap_id\tgene_expression\n")

    buffer = +""
    line_number = 3
    gene_count = 0

    input.each_line do |line|
      line_number += 1
      next if line.strip.empty?

      fields = line.chomp.split("\t", -1)

      if fields.length != expected_column_count
        warn(
          "Invalid column count at line #{line_number}: " \
          "expected #{expected_column_count}, got #{fields.length}"
        )
        exit 1
      end

      ensembl_gene_id = fields[0]
      gene_name = fields[1]
      expression_values = fields.drop(2)

      sample_columns.each_with_index do |(ccle_name, depmap_id), index|
        buffer << ensembl_gene_id << "\t"
        buffer << gene_name << "\t"
        buffer << ccle_name << "\t"
        buffer << depmap_id << "\t"
        buffer << expression_values[index] << "\n"
      end

      if buffer.bytesize >= BUFFER_LIMIT
        output.write(buffer)
        buffer.clear
      end

      gene_count += 1
    end

    output.write(buffer) unless buffer.empty?

    # warn "Converted #{gene_count} genes and #{sample_columns.length} cell lines"
    # warn "Output: #{output_path}"
  end
end
