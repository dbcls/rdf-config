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
            select_variables(add_question_mark: true)
          ].flatten.reject { |term| term.to_s.empty? }.join(' ')
        ]
      end
    end
  end
end
