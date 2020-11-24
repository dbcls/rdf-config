require 'rdf-config/model'
require 'rdf-config/endpoint'
require 'rdf-config/sparql/prefix_generator'
require 'rdf-config/sparql/where_generator'

class RDFConfig
  class Grasp
    class CommentGenerator
      BLOCK_START = '"""'
      BLOCK_END = '"""'

      def initialize(config)
        @config = config

        @model = RDFConfig::Model.new(config)
      end

      def generate
        comment_lines = [BLOCK_START]
        comment_lines += endpoint_lines
        comment_lines << ''
        comment_lines += sparql_lines
        comment_lines << BLOCK_END

        comment_lines
      end

      private

      def endpoint_lines
        endpoint = Endpoint.new(@config)

        lines = ['--- endpoint ---']
        lines << endpoint.primary_endpoint

        lines
      end

      def sparql_lines
        lines = ['--- sparql ---']
        lines += prefix_lines
        lines << ''
        lines += construct_lines
        lines += where_lines

        lines
      end

      def prefix_lines
        prefix_generator = SPARQL::PrefixGenerator.new(@config, variables: @model.object_names, parameters: {}, check_query_name: false)

        lines = ['PREFIX : <https://github.com/dbcls/grasp/ns/>']
        lines += prefix_generator.generate
        lines.pop if lines.last.to_s == ''

        lines
      end

      def construct_lines
        subject_names = []

        lines = ['CONSTRUCT {']
        @model.each do |triple|
          next if triple.predicate.rdf_type?

          subject = triple.subject
          unless subject_names.include?(subject.name)
            subject_names << subject.name
            unless subject.used_as_object?
              lines << "#{INDENT}?#{subject.name} :#{subject.name} ?#{subject.name} ."
            end
          end

          if subject.used_as_object?
            subject.as_object.values.each do |object|
              lines << "#{INDENT}?#{object.name} :#{triple.object_name} ?#{triple.object_name} ."
            end
          else
            lines << "#{INDENT}?#{subject.name} :#{triple.object_name} ?#{triple.object_name} ."
          end
        end
        lines << '}'

        lines
      end

      def where_lines
        where_generator_opts = {
          variables: @model.object_names,
          parameters: {},
          #output_values_line: false,
          indent_text: INDENT,
          check_query_name: false
        }

        where_generator = SPARQL::WhereGenerator.new(@config, where_generator_opts)
        lines = where_generator.generate
        last_line = lines.pop
        lines << ''
        @model.subjects.reject(&:used_as_object?).each do |subject|
          lines << %Q(#{INDENT}{{#if #{subject.name}}}VALUES ?#{subject.name} { {{join " " (as-iriref #{subject.name})}} }{{/if}})
        end
        lines << last_line

        lines
      end
    end
  end
end
