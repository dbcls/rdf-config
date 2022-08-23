require 'rdf-config/grasp/common_methods'
require 'rdf-config/grasp/base'
require 'rdf-config/model/subject'
require 'rdf-config/model/value_list'

class RDFConfig
  class Grasp
    class UnionGenerator < Base
      include CommonMethods

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
        triple.object.value.select { |value| value.is_a?(Model::Subject) }.map { |subject| subject_type_name(@config, subject) }
      end
    end
  end
end
