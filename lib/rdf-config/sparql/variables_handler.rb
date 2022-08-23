require 'rdf-config/model'

class RDFConfig
  class SPARQL
    class VariablesHandler
      @instance = {}

      class << self
        def instance(config, opts)
          key = {
            config_name: config.name,
            opts: opts.to_s
          }

          @instance[key] ||= new(config, opts)
        end
      end

      def variables(config_name)
        @variables[config_name]
      end

      def variables_for_select
        refine_variables(visible_variables)
      end

      def variables_for_where
        variables = (visible_variables + hidden_variables).uniq

        refine_variables(variables)
      end

      def visible_variables
        (
          @variables_by_config + @parameters_by_config.keys + variables_by_query_opts + parameters_by_query_opts.keys
        ).uniq
      end

      def hidden_variables
        variable_names = []

        visible_variables.each do |variable_name|
          next if model.subject?(variable_name)
          next unless (model.parent_subject_names(variable_name) & subjects_by_variables).empty?

          variable_names << closest_subject_name(variable_name)
        end

        variable_names.uniq
      end

      def subject_by_object_name(object_name)
        object = model.find_object(object_name)
        if object.is_a?(Model::Subject)
          subject = object
        else
          subject_name = (model.parent_subject_names(object_name) & variables_for_where).last
          subject = model.find_subject(subject_name)
        end

        subject
      end

      def common_subject_names
        return @common_subject_names if @common_subject_names

        @common_subject_names = model.subjects.map(&:name)
        visible_variables.reject { |variable_name| model.subject?(variable_name) }.each do |object_name|
          @common_subject_names &= model.parent_subject_names(object_name)
        end

        @common_subject_names
      end

      def closest_subject_name(object_name)
        parent_subject_names = model.parent_subject_names(object_name)
        subject_names_in_variables = (parent_subject_names & subjects_by_variables)
        if subject_names_in_variables.empty?
          subject_name = (parent_subject_names & common_subject_names).last
          subject_name = parent_subject_names.first if subject_name.nil?
        else
          subject_name = subject_names_in_variables.last
        end

        subject_name
      end

      def subjects_by_variables
        @subjects_by_variables ||= visible_variables.select { |variable_name| model.subject?(variable_name) }
      end

      def objects_by_variables
        @objects_by_variables ||= visible_variables.reject { |variable_name| model.subject?(variable_name) }
      end

      def valid_variable(variable_name)
        if model.subject?(variable_name)
          variable_name
        else
          triple = model.find_by_object_name(variable_name)
          triple.nil? ? nil : variable_name
        end
      end

      def parameters
        @parameters_by_config.merge(parameters_by_query_opts)
      end

      def variables_by_query_opts
        @variables_by_query_opts[@config.name]
      end

      def parameters_by_query_opts
        @parameters_by_query_opts[@config.name]
      end

      private

      def parse_query_opts(query_opts)
        return if query_opts.nil?

        @opts[:query] = if query_opts.is_a?(Array)
                          query_opts
                        else
                          [query_opts]
                        end

        @opts[:query].each do |var_val|
          variable, value = var_val.split('=', 2)
          config_name, variable_name = variable.split(':')
          if variable_name.nil?
            # No config name: config name is @config.name
            config_name = @config.name
          else
            variable = variable_name
          end

          if value.nil?
            @variables_by_query_opts[config_name] = [] unless @variables_by_query_opts.key?(config_name)
            @variables_by_query_opts[config_name] << variable
          else
            @parameters_by_query_opts[config_name] = {} unless @parameters_by_query_opts.key?(config_name)
            @parameters_by_query_opts[config_name][variable] = value
          end
        end
      end

      def set_variables
        if join?
          set_variables_for_join
        else
          @variables[@config.name] = visible_variables
        end
      end

      def set_variables_for_join
        @configs.each do |config|
          @config = config
          @variables[config.name] = if query?
                                      variables_by_query(config)
                                    else
                                      (variables_by_parameters_config + variables_by_variables_config).uniq
                                    end
        end
      end

      def refine_variables(variable_names)
        variable_names.select { |variable_name| valid_variable?(variable_name) }
      end

      def valid_variable?(variable_name)
        if model.subject?(variable_name)
          true
        else
          triple = model.find_by_object_name(variable_name)
          triple.nil? ? false : true
        end
      end

      def variables_by_query(config)
        prefix = "#{config.name}:"

        @opts[:query].select { |query| query.start_with?(prefix) }.map { |query| query[prefix.length..-1] }
      end

      def join?
        @opts.key?(:join)
      end

      def query?
        @opts.key?(:query)
      end

      def model
        Model.instance(@config)
      end

      def set_config(config)
        @config = config
      end

      def initialize(config, opts)
        if config.is_a?(Array)
          @configs = config
          @config = config.first
        else
          @configs = [config]
          @config = config
        end
        @sparql_name = opts[:query_name]
        @opts = opts

        begin
          @variables_by_config = @config.sparql[@sparql_name]['variables']
          @variables_by_config = [] if @variables_by_config.nil?
        rescue StandardError
          @variables_by_config = []
        end

        begin
          @parameters_by_config = @config.sparql[@sparql_name]['parameters']
          @parameters_by_config = {} if @parameters_by_config.nil?
        rescue StandardError
          @parameters_by_config = {}
        end

        @variables_by_query_opts = {}
        @parameters_by_query_opts = {}
        @configs.each do |config|
          @variables_by_query_opts[config.name] = []
          @parameters_by_query_opts[config.name] = {}
        end

        @variables = {}
        @variables_for_where = {}

        parse_query_opts(opts[:query])
        set_variables
      end
    end
  end
end
