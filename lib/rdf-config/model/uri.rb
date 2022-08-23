require_relative 'object'

class RDFConfig
  class Model
    class URI < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def type
        'URI'
      end

      def uri?
        true
      end
    end
  end
end
