class RDFConfig
  class Model
    class Predicate
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
        %w[a rdf:type].include?(@uri)
      end

      def required?
        @cardinality.nil? || !@cardinality.min.nil? && @cardinality.min.positive?
      end

      def plural?
        !@cardinality.nil? && (@cardinality.max.nil? || @cardinality.max > 1)
      end

      private

      def interpret_cardinality
        last_char = @uri[-1]
        case last_char
        when '?', '*', '+'
          proc_char_cardinality(last_char)
        when '}'
          proc_range_cardinality
        end
      end

      def proc_char_cardinality(cardinality)
        @uri = @uri[0..-2]

        case cardinality
        when '?'
          @cardinality = Cardinality.new(cardinality, 0, 1)
        when '*'
          @cardinality = Cardinality.new(cardinality, 0, nil)
        when '+'
          @cardinality = Cardinality.new(cardinality, 1, nil)
        end
      end

      def proc_range_cardinality
        pos = @uri.rindex('{')
        range = @uri[pos + 1..-2]
        @uri = @uri[0..pos - 1]
        if range.index(',')
          min, max = range.split(/\s*,\s*/)
          @cardinality = Cardinality.new("{#{range}}", min.to_s == '' ? nil : min.to_i, max.to_s == '' ? nil : max.to_i)
        else
          @cardinality = Cardinality.new("{#{range}}", range.to_i, range.to_i)
        end
      end
    end
  end
end
