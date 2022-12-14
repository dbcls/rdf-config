require 'rdf-config/model'
require 'rdf-config/endpoint'
require 'rdf-config/sparql/prefix_generator'
require 'rdf-config/grasp/common_methods'
require 'rdf-config/grasp/base'
require 'rdf-config/grasp/construct_generator'
require 'rdf-config/grasp/where_generator'

class RDFConfig
  class Grasp
    class CommentGenerator < Base
      include CommonMethods

      BLOCK_START = '"""'.freeze
      BLOCK_END = '"""'.freeze

      def initialize(config, opts = {})
        super
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
        lines = ['--- endpoint ---']
        lines << endpoint_url

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
        opts = {
          query: object_names
        }
        prefix_generator = SPARQL::PrefixGenerator.new(@config, opts)

        lines = ['PREFIX : <https://github.com/dbcls/grasp/ns/>']
        lines += prefix_generator.generate
        lines.pop if lines.last.to_s == ''

        lines
      end

      def construct_lines
        ConstructGenerator.new(@config, @opts).generate
      end

      def where_lines
        WhereGenerator.new(@config, @opts).generate
      end
    end
  end
end
