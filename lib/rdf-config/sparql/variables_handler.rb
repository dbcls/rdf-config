require 'rdf-config/model'
require 'rdf-config/sparql/variable'

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
          @instance[key] = new(config, opts) unless @instance.key?(key)

          @instance[key]
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
          @variables_by_config + @parameters_by_config + variables_by_query_opts + parameters_by_query_opts
        ).uniq { |variable| variable.name }
      end

      def hidden_variables
        variables = []

        visible_variables.each do |variable|
          next if model.subject?(variable.name)
          next unless (model.parent_subject_names(variable.name) & subjects_by_variables).empty?

          variables << Variable.new(@config, closest_subject_name(variable.name))
        end

        variables.uniq { |variable| variable.name }
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
        visible_variables.reject { |variable| model.subject?(variable.name) }.each do |variable|
          subject_names = model.parent_subject_names(variable.name)
          # subject_names =
          #   model.routes_by_object_name(variable.name).flatten.map { |triple| triple.subject.name }.uniq
          @common_subject_names &= subject_names
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
        @subjects_by_variables ||= visible_variables.select { |variable| model.subject?(variable.name) }
      end

      def objects_by_variables
        @objects_by_variables ||= visible_variables.reject { |variable| model.subject?(variable.name) }
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
        # TODO 正常に動作するかどうかテストすること！
        parameters_by_query_opts.each do |parameter|
          idx = @parameters_by_config.index(parameter)
          if idx.nil?
            @parameters_by_config << parameter
          else
            @parameters_by_config[idx] = parameter
          end
        end

        @parameters_by_config
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
          variable = Variable.new(@config, var_val)
          if variable.variable?
            @variables_by_query_opts[variable.config_name] = [] unless @variables_by_query_opts.key?(variable.config_name)
            @variables_by_query_opts[variable.config_name] << variable
          elsif variable.parameter?
            @parameters_by_query_opts[variable.config_name] = [] unless @parameters_by_query_opts.key?(variable.config_name)
            @parameters_by_query_opts[variable.config_name] << variable
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

      def refine_variables(variables)
        variables.select { |variable| valid_variable?(variable.name) }
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
        @sparql_name = opts[:sparql]
        @opts = opts

        begin
          @variables_by_config =
            @config.sparql[@sparql_name]['variables'].map { |variable| Variable.new(@config, variable) }
          @variables_by_config = [] if @variables_by_config.nil?
        rescue StandardError
          @variables_by_config = []
        end

        begin
          @parameters_by_config =
            @config.sparql[@sparql_name]['parameters'].map { |name, value| Variable.new(@config, "#{name}=#{value}") }
          @parameters_by_config = [] if @parameters_by_config.nil?
        rescue StandardError
          @parameters_by_config = []
        end

        @variables_by_query_opts = {}
        @parameters_by_query_opts = {}
        @configs.each do |conf|
          @variables_by_query_opts[conf.name] = []
          @parameters_by_query_opts[conf.name] = []
        end

        @variables = {}
        @variables_for_where = {}

        parse_query_opts(opts[:query])
        # puts "@variables_by_config: #{@variables_by_config}"
        # puts "@parameters_by_config: #{@parameters_by_config}"
        # puts "@variables_by_query_opts: #{@variables_by_query_opts}"
        # puts "@parameters_by_query_opts: #{@parameters_by_query_opts}"

        set_variables
      end
    end
  end
end
