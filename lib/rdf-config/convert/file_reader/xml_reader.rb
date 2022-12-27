# frozen_string_literal: true

require 'rexml/document'

class RDFConfig
  class Convert
    class XMLReader
      attr_reader :doc

      def initialize(source_file)
        @source_file = source_file
        @doc = REXML::Document.new(File.read(@source_file))

        @rows_stack = []
        @row_stack = []
        @row = nil
      end

      def each_row(path, &block)
        if @rows_stack.empty?
          @rows_stack.push(REXML::XPath.match(@doc, path))
        else
          if @row.nil?
            return
          else
            @rows_stack.push(REXML::XPath.match(@row, path))
          end
        end

        block.call(fetch_row) until rows.empty?
        delete_rows
      end

      def rows
        @rows_stack.last
      end

      def fetch_row
        @row_stack << rows.shift

        @row = @row_stack.last
      end

      def delete_rows
        @rows_stack.pop
        @row_stack.pop
        @row = @row_stack.last
      end
    end
  end
end
