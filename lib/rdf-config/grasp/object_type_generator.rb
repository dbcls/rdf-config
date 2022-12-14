require 'rdf-config/model'
require 'rdf-config/grasp/data_type'

class RDFConfig
  class Grasp
    class ObjectTypeGenerator
      include DataType

      def initialize(config)
        @model = Model.instance(config)
      end

      def generate(object_type)
        lines = ["type #{object_type} @embedded {"]
        lines += data_type_lines(@model.select { |triple| triple.subject.name == object_type })
        lines << '}'

        lines
      end
    end
  end
end
