# frozen_string_literal: true

require 'rdf/vocab'
require 'rdf/turtle'
require_relative 'mix_in/utils'

class RDFConfig
  class ModelGenerator
    class BaseGenerator
      include MixIn::Utils

      VOCAB = {
        void: RDF::Vocab::VOID,
        class_relation: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#classRelation'),
        subject_class: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#subjectClass'),
        object_class: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectClass'),
        object_datatype: RDF::URI('http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectDatatype')
      }.freeze

      DEFAULT_NAMESPACE = {
        RDF::RDFV.to_s => 'rdf',
        RDF::RDFS.to_s => 'rdfs',
        RDF::XSD.to_s => 'xsd',
        RDF::Vocab::DC.to_s => 'dcterms',
        RDF::Vocab::DC11.to_s => 'dc',
        RDF::Vocab::SKOS.to_s => 'skos',
        RDF::Vocab::FOAF.to_s => 'foaf',
        RDF::Vocab::VOID.to_s => 'void',
        RDF::OWL.to_s => 'owl',
        'http://sparqlbuilder.org/2015/09/rdf-metadata-schema#' => 'sdm',
        'http://www.w3.org/ns/sparql-service-description#' => 'sd',
        'http://purl.obolibrary.org/obo/' => 'obo'
      }

      SUBJECT = 0
      PREDICATE = 1
      OBJECT = 2

      BASE_PREFIX = 'ns'

      PREFIX_YAML_FILE = 'prefix.yaml'
      MODEL_YAML_FILE = 'model.yaml'

      def initialize(input_file, output_dir, **opts)
        @input_file = input_file
        @output_dir = output_dir
        @opts = opts

        @user_defined_namespace = {}
        @new_namespace = {}
        @ns_number = 0

        @triples = []
        @rdf_types = {}

        read_user_defined_prefix

        return if File.exist?(@output_dir)

        require 'fileutils'
        FileUtils.mkdir_p(@output_dir)
      end

      def generate
        parse
        output_model
        output_prefix
        # run_senbero if @opts[:senbero]
      end

      def run_senbero
        if File.exist?(prefix_yaml_file)
          File.foreach(prefix_yaml_file) do |line|
            puts line
          end
          puts
        end

        require 'rdf-config'
        rdf_config = RDFConfig.new(config_dir: @output_dir)
        rdf_config.generate_senbero
      end

      def model_yaml
        subject = {}
        @triples.each do |triple|
          subject_name = subject_name_for(triple[SUBJECT])
          predicate = triple[PREDICATE]
          objects = triple[OBJECT]
          subject[subject_name] = [{ 'a' => qname_for(triple[SUBJECT]) }] unless subject.key?(subject_name)
          subject[subject_name] << hash_for_property(subject_name, predicate, objects)
        end

        subject.map do |subject_name, property_hash|
          { subject_name => property_hash }
        end.to_yaml.sub(/\A---\n/, '')
      end

      def dump_triples
        @triples.each do |triple|
          puts [qname_for(triple[SUBJECT]), qname_for(triple[PREDICATE]), triple[OBJECT].map { |o| qname_for(o) }.join(',')].join("\t")
        end
      end

      def model_yaml_file
        File.join(@output_dir, MODEL_YAML_FILE)
      end

      def prefix_yaml_file
        File.join(@output_dir, PREFIX_YAML_FILE)
      end

      def read_triple_file(triple_file)
        @triples = File.readlines(triple_file).map do |line|
          subject, predicate, object = line.strip.split(/\s+/)
          [subject, predicate, [object]]
        end
      end

      private

      def output_model
        File.open(model_yaml_file, 'w') do |f|
          f.puts model_yaml
        end
      end

      def output_prefix
        File.open(prefix_yaml_file, 'a') do |f|
          @new_namespace.each do |namespace, prefix|
            f.puts "#{prefix}: <#{namespace}>"
          end
        end
      end

      def read_user_defined_prefix
        return unless File.exist?(prefix_yaml_file)

        File.foreach(prefix_yaml_file) do |line|
          prefix, namespace = line.strip.split(/\s*:\s*/, 2).map(&:strip)
          @user_defined_namespace[uri_string(namespace)] = prefix
        end
      end

      def hash_for_property(subject_name, predicate_uri, objects)
        objects = [objects] unless objects.is_a?(Array)
        if rdf_type?(predicate_uri)
          rdf_type = if objects.size == 1
                       qname_for(objects.first)
                     else
                       objects.map { |object| qname_for(object) }
                     end
          { predicate_uri => rdf_type }
        else
          obj_example = if objects.size == 1
                          object_example_value(objects.first)
                        else
                          objects.map { |object| object_example_value(object) }
                        end
          variable_name = variable_name(subject_name, predicate_uri.to_s)
          { qname_for(predicate_uri) => [{ variable_name => obj_example }] }
        end
      end

      def qname_for(uri)
        uri_str = uri_string(uri)
        prefix_uri, local_part = split_uri(uri_str)
        prefix = prefix_for(prefix_uri)
        [prefix, local_part].compact.join(':')
      rescue
        uri
      end

      def prefix_for(namespace)
        prefix = @user_defined_namespace[namespace] || @new_namespace[namespace]
        return prefix unless prefix.nil?

        add_new_namespace(namespace)
      end

      def add_new_namespace(namespace)
        prefix = if DEFAULT_NAMESPACE.key?(namespace)
                   DEFAULT_NAMESPACE[namespace]
                 else
                   generate_prefix
                 end
        @new_namespace[namespace] = prefix

        prefix
      end

      def generate_prefix
        [BASE_PREFIX, @ns_number += 1].join
      end

      def subject_name_for(subject_class_uri)
        namespace, subject_class_local_part = split_uri(subject_class_uri)
        prefix = prefix_for(namespace)
        subject_name = [prefix.to_s, subject_class_local_part].join('_') unless prefix.nil?

        snake_to_camel(subject_name)
      end
    end
  end
end
