# frozen_string_literal: true

require 'rexml/document'

class RDFConfig
  class Convert
    class XMLReader
      def initialize(source_file)
        @source_file = source_file

        @doc = REXML::Document.new(File.read(@source_file))
        @subject_node_stack = [@doc]

        @rows_stack = []
        @row_stack = []
        @row = nil
      end

      def each_row(path, is_subject_node: false, &block)
        @subject_node_stack.push(REXML::XPath.match(@subject_node_stack.last, path)) if is_subject_node

        if @rows_stack.empty?
          @rows_stack.push(REXML::XPath.match(@subject_node_stack.last, path))
        else
          return if @row.nil?

          @rows_stack.push(REXML::XPath.match(@row, path))
        end

        block.call(fetch_row) until rows.empty?
        delete_rows(is_subject_node)
      end

      def rows
        @rows_stack.last
      end

      def fetch_row
        @row_stack << rows.shift

        @row = @row_stack.last
      end

      def delete_rows(is_subject_node)
        @rows_stack.pop
        @row_stack.pop
        @row_stack.last
        @subject_node_stack.pop if is_subject_node
      end
    end
  end
end
