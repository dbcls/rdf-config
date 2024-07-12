require 'rdf/turtle'
require_relative '../rdf_generator'
require_relative '../macros/csv'

class RDFConfig
  class Convert
    class CSV2RDF < RDFGenerator
      def generate
        @convert.source_subject_map.each do |source, subject_names|
          @reader = @convert.file_reader(source: source)
          @subject_names = subject_names
          generate_statements
        end

        refine_statements
        output_rdf
      end

      private

      def generate_statements
        @reader.each_row do |row|
          @converter.push_target_row(row, clear_variable: true)
          generate_by_row(row)
          @converter.pop_target_row
        end
      end

      def generate_by_triple(triple, values, value_idx)
        subject = @subject_node[triple.subject.name][value_idx]
        subject = @subject_node[triple.subject.name].first if subject.nil?
        statement = RDF::Statement.new(
          subject,
          predicate_node(triple.predicate.uri),
          object_node_by_triple(triple, values[value_idx])
        )
        @statements << {
          statement: statement,
          triple: triple
        }
      end

      def add_subject_relation(triple, subject_node, object_node)
        statement = RDF::Statement.new(
          subject_node, predicate_node(triple.predicate.uri), object_node
        )

        @statements << {
          statement: statement,
          triple: triple
        }
      end
    end
  end
end
