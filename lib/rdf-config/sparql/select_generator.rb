class RDFConfig
  class SPARQL
    class SelectGenerator < SPARQL
      def initialize(config, opts = {})
        super

        prepare_sparql_variable_name
      end

      def generate
        [%(SELECT #{variables.map { |name| variable_name_for_sparql(name, true) }.join(' ')})]
      end
    end
  end
end
