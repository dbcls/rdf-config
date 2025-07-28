# frozen_string_literal: true

require_relative '../void'

class RDFConfig
  class ModelGenerator
    class Void
      class QueryParser < Void
        def initialize(input_file, output_dir)
          super

          @graph = RDF::Graph.load(@input_file, format: :turtle)
          @subject_class_uris = []
          @subject_name = {}
          @model = []
        end

        def parse
          fetch_subject_classes
          @subject_class_uris.each do |subject_class|
            # warn subject_uri
            fetch_property_by_subject(subject_class)
          end
        end

        def output_prefix
          File.open(File.join(@output_dir, 'prefix.yaml'), 'w') do |f|
            @namespace.each do |uri, prefix|
              f.puts "#{prefix}: <#{uri}>"
            end
          end
        end

        def output_model
          @subject_class_uris.each do |subject_class_uri|
            subject_name = subject_name_by_class_uri(subject_class_uri)

            subject = {
              subject_name => []
            }
            @property[subject_class_uri].each do |predicate_uri, objects|
              subject[subject_name] << hash_for_property(subject_name, predicate_uri, objects)
            end

            @model << subject
          end

          File.open(File.join(@output_dir, 'model.yaml'), 'w') do |f|
            f.puts Psych.dump(@model).to_s.sub(/^---\n/, '')
          end
          warn "model.yaml and prefix.yaml have been successfully generated in the #{@output_dir}"
        end

        def fetch_subject_classes
          query = RDF::Query.new do
            pattern [:dataset, VOCAB[:void].classPartition, :partition]
            pattern [:partition, VOCAB[:void].class, :resource_class]
          end

          @graph.query(query) do |solution|
            subject_class_uri = solution[:resource_class]
            register_prefix(subject_class_uri)
            add_subject_class_uri(subject_class_uri)
          end
        end

        def fetch_property_by_subject(subject_class)
          @property[subject_class] = { 'a' => [subject_class] }
          fetch_object_class(subject_class)
          fetch_object_datatype(subject_class)
        end

        def fetch_object_class(subject_uri)
          query = RDF::Query.new do
            pattern [:dataset, VOCAB[:void].propertyPartition, :partition]
            pattern [:partition, VOCAB[:void].property, :property_uri]
            pattern [:partition, VOCAB[:class_relation], :class_relation]
            pattern [:class_relation, VOCAB[:subject_class], subject_uri]
            pattern [:class_relation, VOCAB[:object_class], :object_uri]
          end

          @graph.query(query) do |solution|
            predicate_uri = solution[:property_uri]
            object_uri = solution[:object_uri]
            add_property(subject_uri, predicate_uri, object_uri)
          end
        end

        def fetch_object_datatype(subject_uri)
          query = RDF::Query.new do
            pattern [:dataset, VOCAB[:void].propertyPartition, :partition]
            pattern [:partition, VOCAB[:void].property, :property_uri]
            pattern [:partition, VOCAB[:class_relation], :class_relation]
            pattern [:class_relation, VOCAB[:subject_class], subject_uri]
            pattern [:class_relation, VOCAB[:object_datatype], :object_datatype]
          end

          @graph.query(query) do |solution|
            predicate_uri = solution[:property_uri]
            object_datatype = solution[:object_datatype]
            add_property(subject_uri, predicate_uri, object_datatype)
          end
        end

        def dump
          @subject_class_uris.each do |subject_uri|
            puts qname(subject_uri)
            @property[subject_uri].each do |property|
              predicate = rdf_type?(property.first) ? 'a' : qname(property.first)
              object = property.last.map { |object| qname(object) }.join(', ')
              puts "#{indent(1)}#{predicate} #{object}"
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  input_file = ARGV[0]
  output_dir = ARGV[1] || File.join(__dir__, '..', '..', '..', '..', 'work', 'model_generator', 'output')

  unless File.exist?(input_file)
    warn "File not found: #{input_file}"
    exit 1
  end

  warn "input_file: #{input_file}"
  warn "output_dir: #{File.absolute_path(output_dir)}"
  parser = RDFConfig::ModelGenerator::Void::QueryParser.new(input_file, output_dir)
  parser.parse
  parser.dump
  # parser.output_prefix
  # parser.generate_subject_names
  # parser.output_model
end
