class RDFConfig
  class SPARQL
    class SPARQLGenerator
      attr_accessor :offset, :limit

      def initialize
        @offset = nil
        @limit = 100

        @generators = []
      end

      def generate
        sparql_lines = @generators.map(&:generate).flatten
        sparql_lines << offset_limit_line if require_offset_limit?

        sparql_lines
      end

      def add_generator(generator)
        @generators << generator
      end

      def offset_limit_line
        [['OFFSET', @offset], ['LIMIT', @limit]].reject { |ary| ary[1].nil? }.flatten.join(' ')
      end

      def require_offset_limit?
        !@offset.nil? || !@limit.nil?
      end
    end
  end
end
