require 'rdf/turtle'
require_relative '../rdf_generator'
require_relative '../macros/csv'

class RDFConfig
  class Convert
    class CSV2RDF < RDFGenerator
      def initialize(config, convert)
        super

        @subject_node = {}
        @subject_names = []
        @object_names = []
      end

      def generate
        @convert.source_subject_map.each do |source, subject_names|
          @reader = @convert.file_reader(source: source)
          @subject_names = subject_names
          generate_statements
        end

        output_rdf
      end

      def generate_statements
        @reader.each_row do |row|
          @converter.push_target_row(row)
          generate_rdf_by_row(row)
          @converter.pop_target_row
        end
      end

      private

      def generate_rdf_by_row(row)
        clear_subject_node

        process_convert_variable(row)
        generate_rdf_by_subject_names(row)
        generate_subject_relation_statement
      end

      def generate_rdf_by_subject_names(row)
        @subject_names.each do |subject_name|
          values = @converter.convert_value(row, subject_name)
          next if values.empty?

          values = [values] unless values.is_a?(Array)
          values.each do |subject_value|
            node = uri_node(subject_value)
            add_subject_node(subject_name, node)
            @model.find_subject(subject_name).types.each do |rdf_type|
              @statements << RDF::Statement.new(node, RDF.type, uri_node(rdf_type))
            end
          end
          generate_rdf_by_object_names(subject_name, row)
        end
      end

      def generate_rdf_by_object_names(subject_name, row)
        object_names(subject_name).each do |object_name|
          generate_statement_by_object_name(row, object_name)
        end
      end

      def generate_statement_by_object_name(row, object_name)
        values = @converter.convert_value(row, object_name)
        values = [values] unless values.is_a?(Array)
        values.each_with_index do |value, idx|
          next if value.to_s.empty?

          triple = @model.find_by_object_name(object_name)
          # next if triple.nil? || triple.object.is_a?(Model::Subject)
          next if triple.nil?

          subject_name = triple.subject.name
          next unless @subject_node.key?(subject_name)

          generate_statement_by_triple(triple, values, idx)
        end
      end

      def generate_statement_by_triple(triple, values, value_idx)
        subject = @subject_node[triple.subject.name][value_idx]
        subject = @subject_node[triple.subject.name].first if subject.nil?
        @statements << RDF::Statement.new(
          subject,
          predicate_node(triple.predicate.uri),
          object_node_by_triple(triple, values[value_idx])
        )
      end

      def generate_subject_relation_statement
        @subject_node.each do |subject_name, subject_nodes|
          subject_nodes.each do |as_object_node|
            @model.find_all_by_object_name(subject_name).each do |triple|
              next unless @subject_node.key?(triple.subject.name)

              @subject_node[triple.subject.name].each do |subject_node|
                @statements << RDF::Statement.new(
                  subject_node, predicate_node(triple.predicate.uri), as_object_node
                )
              end
            end
          end
        end
      end

      def object_names(subject_name)
        @convert.subject_object_map[subject_name]
      end

      def add_subject_node(subject_name, subject_node)
        @subject_node[subject_name] = [] unless @subject_node.key?(subject_name)
        @subject_node[subject_name] << subject_node
      end

      def clear_subject_node
        @subject_node.clear
      end
    end
  end
end
