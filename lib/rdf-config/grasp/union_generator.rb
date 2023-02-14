require_relative 'base'
require_relative 'common_methods'
require_relative 'data_type'
require_relative '../model/subject'
require_relative '../model/value_list'

class RDFConfig
  class Grasp
    class UnionGenerator < Base
      include CommonMethods
      include DataType

      UNION_TYPE_SEPARATOR = ' | '.freeze

      def initialize(config, opts = {})
        super
      end

      def generate
        lines = []
        triples.select { |triple| triple.object.is_a?(Model::ValueList) }.each do |triple|
          lines << union_line(triple)
        end

        lines
      end

      def union_line(triple)
        types = union_types(triple)
        return if types.empty?

        "union #{union_type_name(@config, triple.object)} = #{types.join(UNION_TYPE_SEPARATOR)}"
      end

      def union_types(triple)
        triple.object.value.select { |value| value.is_a?(Model::Subject) }.map { |subject| subject_type_name(@config, subject, add_namespace: @add_namespace) }
      end
    end
  end
end
