require_relative 'object'

class RDFConfig
  class Model
    class Unknown < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def instance_type
        'N/A'
      end
    end
  end
end
