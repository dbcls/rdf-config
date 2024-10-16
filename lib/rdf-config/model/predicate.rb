class RDFConfig
  class Model
    class Predicate
      RDF_TYPES = %(a rdf:type).freeze

      class << self
        def rdf_type?(uri)
          RDF_TYPES.include?(uri.to_s)
        end
      end

      attr_reader :name, :uri, :objects, :cardinality

      def initialize(predicate, prefix_hash = {})
        @name = predicate
        @uri = predicate == 'a' ? 'rdf:type' : predicate
        @prefix_hash = prefix_hash
        @cardinality = nil

        @objects = []

        interpret_cardinality
      end

      def add_object(object)
        @objects << object
      end

      def rdf_type?
        @name == 'a' || self.class.rdf_type?(@uri)
      end

      def required?
        @cardinality.nil? || @cardinality.required?
      end

      def plural?
        !@cardinality.nil? && (@cardinality.max.nil? || @cardinality.max > 1)
      end

      def quantifier
        @cardinality&.quantifier
      end

      private

      def interpret_cardinality
        last_char = @uri[-1]
        case last_char
        when '?', '*', '+'
          proc_char_cardinality(last_char)
        when '}'
          proc_range_cardinality
        else
          @cardinality = Cardinality.new('')
        end

        @uri == 'rdf:type' if @uri == 'a'
      end

      def proc_char_cardinality(quantifier)
        @uri = @uri[0..-2]

        @cardinality = Cardinality.new(quantifier)
      end

      def proc_range_cardinality
        pos = @uri.rindex('{')
        quantifier = @uri[pos..-1]
        @uri = @uri[0..pos - 1]
        @cardinality = Cardinality.new(quantifier)
      end
    end
  end
end
