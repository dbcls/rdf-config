class RDFConfig
  class SPARQL
    class SPARQLGenerator
      def initialize
        @offset = nil
        @limit = 100

        @generators = []
      end

      def generate
        @generators.map(&:generate).flatten
      end

      def add_generator(generator)
        @generators << generator
      end
    end
  end
end
