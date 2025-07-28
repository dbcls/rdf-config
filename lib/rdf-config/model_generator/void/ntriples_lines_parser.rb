# frozen_string_literal: true

require_relative '../void'
require_relative '../mix_in/ntriples'

class RDFConfig
  class ModelGenerator
    class Void
      class NTriplesLinesParser < Void
        include MixIn::NTriples

        def initialize(input_file, output_dir, **opts)
          super
        end

        def parse
          line_number = 1
          File.foreach(@input_file) do |triple|
            process_void_triple(triple)
            warn "Raad #{line_number} lines done. (#{@triples.size} triples)" if line_number % 10000 == 0
            line_number += 1
          end
        end

        def dump_sd_graph
          @sd_graph.each do |subject, sd_graph|
            # puts "#{subject} (#{@rdf_types[subject].map { |s| qname(s) }.join(', ')})"
            puts "#{subject} (#{@rdf_types[subject].map { |s| qname(s[1..-2]) }.join(', ')})"
            puts "#{indent(1)}classPartitions:"
            sd_graph[:class_partitions].each do |class_partition_subject|
              puts "#{indent(2)}#{class_partition_subject}"
              puts "#{indent(3)}subject_class_uri: #{qname(@class_partition[class_partition_subject][:subject_class_uri])}"
            end

            puts "#{indent(1)}propertyPartitions:"
            sd_graph[:property_partitions].each do |property_partition_subject|
              class_relation_subject = @property_partition[property_partition_subject][:class_relation_subject]
              puts "#{indent(2)}#{property_partition_subject}"
              puts "#{indent(3)}predicate_uri:  #{qname(@property_partition[property_partition_subject][:predicate_uri])}"
              puts "#{indent(3)}class_relation: #{class_relation_subject}"
              puts "#{indent(4)}rdf:type: #{@rdf_types[class_relation_subject].map { |rdf_type| qname(rdf_type) }.join(', ')}"
              puts "#{indent(4)}subject_class_uri: #{qname(@class_relation[class_relation_subject][:subject_class_uri])}"
              puts "#{indent(4)}object_class_uri : #{qname(@class_relation[class_relation_subject][:object_class_uri])}"
              puts "#{indent(4)}object_datatype  : #{qname(@class_relation[class_relation_subject][:object_datatype])}"
            end
          end
        end

        private

        def process_void_triple(triple)
          subject, predicate, object, _ = triple.split(/\s+/)
          case predicate
          when '<http://rdfs.org/ns/void#propertyPartition>'
            # add_sd_graph(subject)
            # @sd_graph[subject][:property_partitions] << object
            add_property_partition(object)
          when '<http://rdfs.org/ns/void#property>'
            add_property(subject, object)
            add_triple_by_property_partition_object(subject)
          when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#classRelation>'
            add_class_relation(object, property_partition_object: subject)
            add_triple_by_class_relation_subject(object)
          when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#subjectClass>'
            add_class_relation_subject_uri(subject, object)
            add_triple_by_class_relation_subject(subject)
          when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectDatatype>'
            add_class_relation_object_datatype(subject, object)
            add_triple_by_class_relation_subject(subject)
          when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectClass>'
            add_class_relation_object_class(subject, object)
            add_triple_by_class_relation_subject(subject)
          # when '<http://rdfs.org/ns/void#classPartition>'
          #   add_sd_graph(subject)
          #   @sd_graph[subject][:class_partitions] << object
          #   @class_partition[object] = {} unless @class_partition.key?(object)
          # when '<http://rdfs.org/ns/void#class>'
          #   @class_partition[subject] = {} unless @class_partition.key?(subject)
          #   @class_partition[subject][:subject_class_uri] = object
          # when '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
          #   @rdf_types[subject] = [] unless @rdf_types.key?(subject)
          #   @rdf_types[subject] << object
          end
        end

        def add_sd_graph(subject)
          return if @sd_graph.key?(subject)

          @sd_graph[subject] = {
            class_partitions: [],
            property_partitions: []
          }
        end

        def add_property_partition(property_partition_object)
          return if @property_partition.key?(property_partition_object)

          @property_partition[property_partition_object] = {}
        end

        def add_property(property_partition_object, predicate_uri)
          add_property_partition(property_partition_object)
          @property_partition[property_partition_object][:predicate_uri] = predicate_uri
        end

        def add_class_relation(class_relation_subject, property_partition_object: nil)
          add_property_partition(property_partition_object)
          @property_partition[property_partition_object][:class_relation_subject] = class_relation_subject

          unless @class_relation.key?(class_relation_subject)
            @class_relation[class_relation_subject] = {}
          end

          return if property_partition_object.nil?

          @class_relation[class_relation_subject][:property_partition_object] = property_partition_object
        end

        def add_class_relation_subject_uri(class_relation_subject, subject_class_uri)
          add_class_relation(class_relation_subject)
          @class_relation[class_relation_subject][:subject_class_uri] = subject_class_uri
        end

        def add_class_relation_object_datatype(class_relation_subject, object_datatype)
          add_class_relation(class_relation_subject)
          @class_relation[class_relation_subject][:object_datatype] = object_datatype
        end

        def add_class_relation_object_class(class_relation_subject, object_class)
          add_class_relation(class_relation_subject)
          @class_relation[class_relation_subject][:object_class] = object_class
        end

        def add_triple_by_property_partition_object(property_partition_object)
          class_relation_subject = @property_partition[property_partition_object][:class_relation_subject]
          return if class_relation_subject.nil?

          add_triple_by_class_relation_subject(class_relation_subject)
        end

        def add_triple_by_class_relation_subject(class_relation_subject)
          return unless triple_complete?(class_relation_subject)

          subject = @class_relation[class_relation_subject][:subject_class_uri]
          predicate = predicate_uri(@class_relation[class_relation_subject][:property_partition_object])
          object = @class_relation[class_relation_subject][:object_datatype] || @class_relation[class_relation_subject][:object_class_uri]

          add_triple(subject, predicate, object)

          delete_cache(class_relation_subject)
        end

        def triple_complete?(class_relation_subject)
          property_partition_object = @class_relation[class_relation_subject][:property_partition_object]
          return false if property_partition_object.nil?

          property_partition_complete?(property_partition_object) && class_relation_complete?(class_relation_subject)
        end

        def property_partition_complete?(property_partition_object)
          !@property_partition[property_partition_object][:class_relation_subject].nil? &&
            !@property_partition[property_partition_object][:predicate_uri].nil?
        end

        def class_relation_complete?(class_relation_subject)
          !@class_relation[class_relation_subject][:property_partition_object].nil? &&
            !@class_relation[class_relation_subject][:subject_class_uri].nil? &&
            (!@class_relation[class_relation_subject][:object_class_uri].nil? ||
              !@class_relation[class_relation_subject][:object_datatype].nil?)
        end

        def delete_cache(class_relation_subject)
          @class_relation.delete(class_relation_subject)
          @property_partition.delete_if { |k, v| k == :class_relation_subject && v == class_relation_subject }
        end

        def predicate_uri(property_partition_object)
          @property_partition[property_partition_object][:predicate_uri]
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  # 76,324,970 lines
  input_file = File.join(ENV['HOME'], 'Works/DBCLS/RDF-config-Models/VoID/input/pdbj__dataset_pdbj.nt')
  output_dir = File.join(ENV['HOME'], 'Works/DBCLS/RDF-config-Models/VoID/output/by-lines5')

  unless File.exist?(input_file)
    warn "File not found: #{input_file}"
    exit 1
  end

  model_triple_file = File.join(ENV['HOME'], 'Works/DBCLS/RDF-config-Models/VoID/output/by-lines/pdbj__dataset_pdbj-triples.txt')
  model_generator = RDFConfig::ModelGenerator::Void::NTriplesLinesParser.new(input_file, output_dir)
  # model_generator.read_triple_file(model_triple_file)
  # puts model_generator.model_yaml
  model_generator.parse

  # input_file = ARGV[0]
  # output_dir = ARGV[1] || File.join(__dir__, '..', '..', '..', '..', 'work', 'model_generator', 'output')
  # parser = RDFConfig::ModelGenerator::Void::NTriplesLinesParser.new(input_file, output_dir)
  # parser.generate
end
