require 'csv'
require_relative '../../../../rust/rust_tsv/rust_tsv'
require_relative 'row_adapter'

class RDFConfig
  class Convert
    class CSVReader
      BATCH_SIZE = 10000

      def initialize(source_file, file_format)
        @source_file = source_file
        case file_format
        when 'csv'
          @col_sep = ','
        when 'tsv'
          @col_sep = "\t"
        end

        @line_no = 1
      end

      def each_row(use_rust: true, &block)
        if use_rust
          RustTsv.each_batch(@source_file, true, BATCH_SIZE) do |header, rows|
            rows.each do |fields|
              row = RowAdapter.new(header, fields)
              block.call(row)
            end
          end
        else
          CSV.foreach(@source_file, **csv_opts) do |row|
            block.call(row)
          end
        end
      end

      def source
        File.basename(@source_file)
      end

      private

      def csv_opts
        opts = {
          col_sep: @col_sep,
          headers: :first_row
        }

        if @col_sep == "\t"
          opts[:quote_char] = nil
        end

        opts
      end
    end
  end
end
