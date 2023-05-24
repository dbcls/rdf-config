require 'json'

class RDFConfig
  class Convert
    class JSONReader
      def initialize(source_file)
        @source_file = source_file
        @json_hash = JSON.parse(File.read(@source_file))

        @rows_stack = []
        @row = nil
      end

      def each_row(path, is_subject_node: false, &block)
        if @rows_stack.empty?
          @rows_stack.push(@json_hash[path])
        else
          @rows_stack.push(@row[path])
        end

        block.call(fetch_row) until rows.empty?
        delete_rows
      end

      def rows
        @rows_stack.last
      end

      def fetch_row
        @row = rows.shift
      end

      def delete_rows
        @rows_stack.pop
      end
    end
  end
end
