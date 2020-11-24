require 'rdf-config/model'
require 'rdf-config/grasp/data_type'

class RDFConfig
  class Grasp
    class QueryGenerator
      include DataType

      def initialize(config)
        @prefix = config.prefix
        @model = Model.new(config)
      end

      def generate
        ds_subject = dataset_subject(@model)

        lines = ['query {']
        lines << %Q/#{INDENT}dataset(#{ds_subject.name}: "#{subject_value(ds_subject)}") {/
        lines << "#{INDENT * 2}#{ds_subject.name}"
        @model.select { |triple| triple.subject.name == ds_subject.name }.each do |triple|
          next if triple.predicate.rdf_type?

          case triple.object
          when Model::Subject
            lines << "#{INDENT * 2}#{triple.object_name} {"
            lines += variable_name_lines_by_subject(triple.object, 3)
            lines << "#{INDENT * 2}}"
          else
            lines << "#{INDENT * 2}#{triple.object.name}"
          end
        end
        lines << "#{INDENT}}"
        lines << '}'

        lines
      end

      private

      def subject_value(subject)
        if subject.value =~ /\A<.+>\z/
          subject.value[1 .. -2]
        else
          prefix, local_part = subject.value.split(':', 2)
          "#{@prefix[prefix].to_s[1 .. -2]}#{local_part}"
        end
      end

      def variable_name_lines_by_subject(subject, depth)
        lines = []
        @model.select { |triple| triple.subject.name == subject.name }.each do |triple|
          next if triple.predicate.rdf_type?

          lines << "#{INDENT * depth}#{triple.object_name}"
        end

        lines
      end
    end
  end
end
