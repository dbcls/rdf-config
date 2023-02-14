require_relative '../model'
require_relative 'common_methods'
require_relative 'data_type'

class RDFConfig
  class Grasp
    class QueryTypeGenerator
      include CommonMethods
      include DataType

      DEFAULT_TYPE_NAME = 'Query'.freeze
      QUERY_ARGS = [
        { name: IRI_ARG_NAME, type: '[String]' },
        { name: ID_ARG_NAME, type: '[String]'}
      ]

      def initialize(opts = {})
        @add_namespace = opts[:add_namespace]

        @query_lines = []
      end

      def generate
        lines = ['directive @embedded on OBJECT']
        lines << ''
        lines << "type #{type_name} {"
        @query_lines.each do |line|
          lines << line
        end
        lines << '}'

        lines
      end

      def generate_by_config(config)
        Model.instance(config).subjects.each do |subject|
          add(config, subject)
        end
      end

      def add(config, subject)
        type = subject_type_name(config, subject, add_namespace: @add_namespace)
        @query_lines << "#{INDENT}#{type}(#{arg_string}): [#{type}]!"
      end

      private

      def arg_string
        QUERY_ARGS.map { |arg| "#{arg[:name]}: #{arg[:type] } "}.join(', ')
      end

      def type_name
        DEFAULT_TYPE_NAME
      end
    end
  end
end
