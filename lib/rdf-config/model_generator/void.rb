# frozen_string_literal: true

require 'rdf/vocab'
require 'rdf/turtle'
require_relative 'mix_in/utils'

class RDFConfig
  class ModelGenerator
    class Void
      include MixIn::Utils

      VOCAB = {
        void: RDF::Vocab::VOID,
        class_relation: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#classRelation'),
        subject_class: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#subjectClass'),
        object_class: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectClass'),
        object_datatype: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectDatatype')
      }.freeze

      def initialize(input_file, input_format, output_dir)
        @input_file = input_file
        @input_format = input_format
        @output_dir = output_dir

        @graph = RDF::Graph.load(@input_file, format: :turtle)
        @subject_class_uris = []
        @subject_name = {}
        @property = {}
        @prefix = {}
        @ns_number = 1
        @model = []

        return if File.exist?(@output_dir)

        require 'fileutils'
        FileUtils.mkdir_p(@output_dir)
      end

      def generate
        parse
        output_prefix
        generate_subject_names
        output_model
      end

      private

      def parse
        fetch_subject_uris
        @subject_class_uris.each do |subject_uri|
          # warn subject_uri
          fetch_property_by_subject(subject_uri)
        end
      end

      def output_prefix
        File.open(File.join(@output_dir, 'prefix.yaml'), 'w') do |f|
          @prefix.each do |uri, prefix|
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
          @property[subject_class_uri].each do |predicate_uri, object|
            obj_example = if object.is_a?(Array)
                            object.map { |obj| object_example_value(obj) }
                          else
                            object_example_value(object)
                          end
            variable_name = variable_name(subject_name, predicate_uri.to_s)
            predicate_object = { qname(predicate_uri) => [{ variable_name => obj_example }] }
            subject[subject_name] << predicate_object
          end

          @model << subject
        end

        File.open(File.join(@output_dir, 'model.yaml'), 'w') do |f|
          f.puts Psych.dump(@model).to_s.sub(/^---\n/, '')
        end
        warn "model.yaml and prefix.yaml have been successfully generated in the #{@output_dir}"
      end

      def fetch_subject_uris
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

      def fetch_property_by_subject(subject_uri)
        @property[subject_uri] = {}
        fetch_object_class(subject_uri)
        fetch_object_datatype(subject_uri)
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
            puts "    #{qname(property[:predicate])} #{qname(property[:object])}"
          end
        end
      end

      def generate_subject_names
        @subject_name = @subject_class_uris.map { |uri| [uri, subject_name_by_class_uri(uri)] }.to_h
      end

      def add_subject_class_uri(subject_class_uri)
        @subject_class_uris << subject_class_uri
      end

      def add_property(subject_uri, predicate_uri, object)
        register_prefix(predicate_uri)
        register_prefix(object)

        if @property[subject_uri].key?(predicate_uri)
          if @property[subject_uri][predicate_uri].is_a?(Array)
            @property[subject_uri][predicate_uri] << object
          else
            @property[subject_uri][predicate_uri] = [
              @property[subject_uri][predicate_uri], object
            ]
          end
        else
          @property[subject_uri][predicate_uri] = object
        end
      end

      def register_prefix(uri)
        prefix_uri, = split_uri(uri)
        return if @prefix.key?(prefix_uri)

        vocab = RDF::Vocabulary.find(prefix_uri)
        if vocab
          @prefix[prefix_uri] = vocab.__prefix__
        else
          @prefix[prefix_uri] = "ns#{@ns_number}"
          @ns_number += 1
        end
      end

      def read_prefixes
        File.foreach(@input_file) do |line|
          next unless line.strip.start_with?('@prefix')

          match = line.match(/@prefix\s+(\w+):\s+<([^>]+)>\s*\./)
          if match
            prefix = match[1]
            uri = match[2]
            @prefixes[prefix] = uri
          end
        end
      end

      def read_turtle
        RDF::Turtle::Reader.open(@input_file) do |reader|
          reader.each_statement do |statement|
            puts statement.inspect
          end
        end
      end
    end
  end
end
