# frozen_string_literal: true

require 'rdf/vocab'
require 'rdf/turtle'
require_relative 'base_generator'
require_relative 'mix_in/utils'

class RDFConfig
  class ModelGenerator
    class Void < BaseGenerator
      def initialize(input_file, output_dir, **opts)
        super

        @sd_graph = {}
        @class_partition = {}
        @property_partition = {}
        @class_relation = {}
      end

      private

      def add_triple(subject_class_uri, predicate_uri, object)
        subject_class_uri = uri_string(subject_class_uri)
        predicate_uri = uri_string(predicate_uri)
        object = uri_string(object)

        # triple = @triples.find do |triple|
        #   triple[SUBJECT] == subject_class_uri && triple[PREDICATE] == predicate_uri
        # end

        # if triple.nil?
        #   @triples << [subject_class_uri, predicate_uri, [object]]
        # else
        #   triple[OBJECT] << object unless triple[2].include?(object)
        # end

        @triples << [subject_class_uri.dup, predicate_uri.dup, object.dup]
      end

      def generate_subject_names
        @subject_name = @subject_class_uris.map { |uri| [uri, subject_name_by_class_uri(uri)] }.to_h
      end

      def add_subject_class_uri(subject_class_uri)
        @subject_class_uris << subject_class_uri unless @subject_class_uris.include?(subject_class_uri)
      end

      def add_property(subject_uri, predicate_uri, object)
        register_prefix(predicate_uri)
        register_prefix(object)

        return if @property[subject_uri].key?(predicate_uri) && @property[subject_uri][predicate_uri].include?(object)

        if @property[subject_uri].key?(predicate_uri)
          @property[subject_uri][predicate_uri] << object
        else
          @property[subject_uri][predicate_uri] = [object]
        end
      end

      def register_prefix(uri)
        prefix_uri, = split_uri(uri)
        return if @namespace.key?(prefix_uri)

        vocab = RDF::Vocabulary.find(prefix_uri)
        if vocab
          @namespace[prefix_uri] = vocab.__prefix__
        else
          @namespace[prefix_uri] = "ns#{@ns_number}"
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
            @namespace[uri] = prefix
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
