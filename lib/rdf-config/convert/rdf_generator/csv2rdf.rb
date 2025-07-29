require 'rdf/turtle'
require_relative '../rdf_generator'
require_relative '../macros/csv'

class RDFConfig
  class Convert
    class CSV2RDF < RDFGenerator
      def generate
        output_prefixes if turtle_format?

        @convert.source_subject_map.each do |source, subject_names|
          @source = source
          @subject_names = subject_names

          file_format = @convert.source_format_map[source].first
          @reader = @convert.file_reader(source: source, file_format: file_format)
          generate_statements
        end

        # refine_statements
        # output_rdf
      end

      private

      def generate_statements
        line_number = 1
        @reader.each_row do |row|
          @converter.push_target_row(row, clear_variable: true)
          generate_by_row(row)
          add_statements_for_row
          clear_bnode_cache
          @converter.pop_target_row

          # if line_number % READ_DONE_LINES == 0
          #   warn "#{@reader.source}: #{line_number.delimited_string} lines have been read."
          # end

          if @convert.output_interval.positive? && (line_number % @convert.output_interval) == 0
            # warn "Generating #{format_text} data ..."
            # refine_statements
            output_rdf
          end

          line_number += 1
        end

        # warn "#{@reader.source}: Finished reading the input data."
        # warn "Generating #{format_text} data ..."
        # refine_statements
        output_rdf
      end

      def generate_by_triple(triple, values, value_idx)
        subject = @subject_node[triple.subject.name][value_idx]
        subject = @subject_node[triple.subject.name].first if subject.nil?
        statement = RDF::Statement.new(
          subject,
          predicate_node(triple.predicate.uri),
          object_node_by_triple(triple, values[value_idx])
        )
        @one_row_statements << {
          statement: statement,
          triple: triple
        }
      end

      def add_subject_relation(triple, subject_node, object_node)
        statement = RDF::Statement.new(
          subject_node, predicate_node(triple.predicate.uri), object_node
        )

        @one_row_statements << {
          statement: statement,
          triple: triple
        }
      end
    end
  end
end
