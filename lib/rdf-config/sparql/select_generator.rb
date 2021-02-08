class RDFConfig
  class SPARQL
    class SelectGenerator < SPARQL
      def initialize(config, opts = {})
        super

        #prepare_sparql_variable_name
      end

      def generate
        [%(SELECT #{valid_variables.map { |name| variable_name_for_sparql(name, true) }.join(' ')})]
      end
    end
  end
end
