require_relative 'object'

class RDFConfig
  class Model
    class URI < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def instance_type
        'URI'
      end

      def shex_data_type
        'IRI'
      end

      def uri?
        true
      end

      def literal?
        false
      end
    end
  end
end
