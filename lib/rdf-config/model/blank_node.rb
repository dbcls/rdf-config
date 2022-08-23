require_relative 'object'

class RDFConfig
  class Model
    class BlankNode < RDFConfig::Model::Object
      def initialize(object, prefixe_hash = {})
        super
        @value = Subject.new({ @name => @value }, prefixe_hash)
      end

      def type
        'BNODE'
      end

      def blank_node?
        true
      end

      def rdf_type_uri
        @name
      end

      def as_subject
        @value
      end
    end
  end
end
