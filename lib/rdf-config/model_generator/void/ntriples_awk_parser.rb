# frozen_string_literal: true

require_relative '../void'
require_relative '../mix_in/ntriples'

class RDFConfig
  class ModelGenerator
    class Void
      class NTriplesAwkParser < Void
        include MixIn::NTriples

        def initialize(input_file, output_dir)
          super

          @property_partition_subjects = []
          @triples = []
        end

        def parse
          fetch_property_partition_subjects
          @property_partition_subjects.each do |property_partition_subject|
            # warn "property_partition_subject: #{property_partition_subject}"
            property_partition = parse_property_partition_triples(property_partition_subject)
            # next unless property_partition[:class_is_void_dataset]

            process_property_partition(property_partition)
          end
        end

        def process_property_partition(property_partition)
          predicate_uri = property_partition[:predicate_uri]
          property_partition[:class_partition_subjects].each do |class_partition_subject|
            # warn "    class_partition_subject: #{class_partition_subject}"
            process_class_partition(class_partition_subject, predicate_uri)
          end
        end

        def process_class_partition(class_partition_subject, predicate_uri)
          class_relation = parse_class_relation_triples(class_partition_subject)
          return unless class_relation[:class_is_class_relation]

          add_triple(
            class_relation[:subject_class_uri],
            predicate_uri,
            class_relation[:object_class_uri] || class_relation[:object_datatype]
          )
        end

        def fetch_property_partition_subjects
          predicate = '<http://rdfs.org/ns/void#propertyPartition>'
          awk_cmd = [
            "awk",
            "-v", "p=#{predicate}",
            '$2 == p',
            # "-v", "o=#{object}",
            # '$2 == p && $3 == o',
            @input_file
          ]
          IO.popen(awk_cmd, "r") do |io|
            io.each_line do |line|
              @property_partition_subjects << line.split(/\s+/)[2]
            end
          end
        end

        def parse_property_partition_triples(property_partition_subject)
          class_is_void_dataset = false
          predicate_uri = nil
          class_partition_subjects = []

          awk_cmd = [
            "awk",
            "-v", "s=#{property_partition_subject}",
            '$1 == s',
            # "-v", "o=#{object}",
            # '$2 == p && $3 == o',
            @input_file
          ]
          IO.popen(awk_cmd, "r") do |io|
            io.each_line do |line|
              _, predicate, object, _ = line.split(/\s+/)
              case predicate
              when '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
                class_is_void_dataset = true if object == '<http://rdfs.org/ns/void#Dataset>'
              when '<http://rdfs.org/ns/void#property>'
                predicate_uri = object
              when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#classRelation>'
                class_partition_subjects << object
              end
            end
          end

          {
            class_is_void_dataset: class_is_void_dataset,
            predicate_uri: predicate_uri,
            class_partition_subjects: class_partition_subjects
          }
        end

        def parse_class_relation_triples(class_partition_subject)
          class_is_class_relation = false
          subject_class_uri = nil
          object_class_uri = nil
          object_datatype = nil

          awk_cmd = [
            "awk",
            "-v", "s=#{class_partition_subject}",
            '$1 == s',
            # "-v", "o=#{object}",
            # '$2 == p && $3 == o',
            @input_file
          ]
          IO.popen(awk_cmd, "r") do |io|
            io.each_line do |line|
              _, predicate, object, _ = line.split(/\s+/)
              case predicate
              when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#subjectClass>'
                subject_class_uri = object
              when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectClass>'
                object_class_uri = object
              when '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#objectDatatype>'
                object_datatype = object
              when '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
                class_is_class_relation = true if object == '<http://sparqlbuilder.org/2015/09/rdf-metadata-schema#ClassRelation>'
              end
            end
          end

          {
            class_is_class_relation: class_is_class_relation,
            subject_class_uri: subject_class_uri,
            object_class_uri: object_class_uri,
            object_datatype: object_datatype
          }
        end

        def add_triple(subject, predicate, object)
          return if @triples.include?([subject, predicate, object])

          @triples << [subject, predicate, object]
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
  parser = RDFConfig::ModelGenerator::Void::NTriplesAwkParser.new(input_file, output_dir)
  parser.parse
  parser.output_triples
end
