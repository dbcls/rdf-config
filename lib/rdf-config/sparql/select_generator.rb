class RDFConfig
  class SPARQL
    class SelectGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        [
          [
            'SELECT',
            distinct? ? 'DISTINCT' : '',
            valid_variables.map { |name| variable_name_for_sparql(name, true) }
          ].flatten.reject { |term| term.to_s.empty? }.join(' ')
        ]
      end
    end
  end
end
