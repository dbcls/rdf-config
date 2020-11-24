require 'rdf-config/model'
require 'rdf-config/grasp/data_type'

class RDFConfig
  class Grasp
    class DatasetTypeGenerator
      include DataType

      def initialize(config)
        @config = config

        @model = RDFConfig::Model.new(config)
      end

      def generate
        lines = ['type Dataset {']
        lines += data_type_lines(@model.select { |triple| triple.subject.name == dataset_subject(@model).name })
        lines << '}'

        lines
      end
    end
  end
end
