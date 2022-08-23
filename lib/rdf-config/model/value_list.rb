require_relative 'object'

class RDFConfig
  class Model
    class ValueList < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end
    end
  end
end
