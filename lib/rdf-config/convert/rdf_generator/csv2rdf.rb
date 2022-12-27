require 'rdf/turtle'
require_relative '../rdf_generator'

class RDFConfig
  class Convert
    class CSV2RDF < RDFGenerator
      def initialize(config, reader, converter)
        super

        @subject_node_map = {}
      end

      def generate
        RDF::Writer.for(:turtle).new(prefixes: @prefixes, canonicalize: true) do |writer|
          @reader.each_row do |row|
            generate_rdf_by_row(writer, row)
          end
        end
      end

      def generate_rdf_by_row(writer, row)
        @subject_node_map.clear

        generate_rdf_by_subject_names(writer, row)
        generate_subject_relation_rdf(writer)
        generate_rdf_by_object_names(writer, row)
      end

      def generate_rdf_by_subject_names(writer, row)
        subject_names.each do |subject_name|
          values = @converter.convert_value(row, subject_name)
          next if values.empty?

          @subject_node_map[subject_name] = [] unless @subject_node_map.key?(subject_name)
          values = [values] unless values.is_a?(Array)
          values.each do |subject_value|
            node = uri_node(subject_value)
            @subject_node_map[subject_name] << node
            @model.find_subject(subject_name).types.each do |rdf_type|
              writer << RDF::Statement.new(node, RDF.type, uri_node(rdf_type))
            end
          end
        end
      end

      def generate_subject_relation_rdf(writer)
        @subject_node_map.each do |subject_name, subject_nodes|
          subject_nodes.each do |as_object_node|
            @model.find_all_by_object_name(subject_name).each do |triple|
              next unless @subject_node_map.key?(triple.subject.name)

              @subject_node_map[triple.subject.name].each do |subject_node|
                writer << RDF::Statement.new(
                  subject_node, predicate_node(triple.predicate.uri), as_object_node
                )
              end
            end
          end
        end
      end

      def generate_rdf_by_object_names(writer, row)
        object_names.each do |object_name|
          values = @converter.convert_value(row, object_name)
          values = [values] unless values.is_a?(Array)
          values.each_with_index do |value, i|
            next if value.to_s.empty?

            triple = @model.find_by_object_name(object_name)
            next if triple.nil? || triple.object.is_a?(Model::Subject)

            subject_name = triple.subject.name
            next unless @subject_node_map.key?(subject_name)

            subject = @subject_node_map[triple.subject.name][i]
            subject = @subject_node_map[triple.subject.name].first if subject.nil?
            writer << RDF::Statement.new(
              subject,
              predicate_node(triple.predicate.uri),
              object_node_by_triple(triple, values[i])
            )
          end
        end
      end
    end
  end
end
