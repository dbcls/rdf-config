require 'rdf-config/model'

class RDFConfig
  class Grasp
    class QueryTypeGenerator
      def initialize(config)
        @model = RDFConfig::Model.new(config)
      end

      def generate
        lines = ['directive @embedded on OBJECT']
        lines << ''
        lines << 'type Query {'
        lines << "#{INDENT}dataset(#{@model.subjects.first.name}: String): Dataset"
        @model.subjects.select(&:used_as_object?).each do |subject|
          lines << "#{INDENT}#{subject.name}(#{subject.name}: String): #{subject.name}"
        end
        lines << '}'
      end
    end
  end
end
