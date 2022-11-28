require 'csv'

class RDFConfig
  class Convert
    class CsvReader
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

      def read
        rows = []
        CSV.foreach(@source_file, col_sep: @col_sep, headers: :first_row) do |row|
          rows << row
          @line_no += 1
          break if @line_no > 10
        end

        rows
      end
    end
  end
end
