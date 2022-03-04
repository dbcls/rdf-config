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
            valid_variables
          ].flatten.reject { |term| term.to_s.empty? }.join(' ')
        ]
      end

      def valid_variables
        #--> if query?
        if join?
          valid_variables_by_query
        else
          #--> super.map { |name| variable_name_for_sparql(name, true) }
          @variables_handler.variables_for_select.map { |name| variable_name_for_sparql(name, true) }
        end
      end

      def valid_variables_by_query
        variable_names = []
        @opts[:query].each do |query|
          config_name, variable_name = query.split(':')
          @config = @configs.select { |config| config.name == config_name }.first
          name = valid_variable(variable_name)
          variable_names << variable_name_for_sparql(name, true) unless name.nil?
        end

        variable_names.uniq
      end
    end
  end
end
