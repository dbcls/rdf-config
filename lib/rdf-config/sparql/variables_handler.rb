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
          variables_by_config + parameters_by_config + variables_by_query_opts + parameters_by_query_opts
        ).uniq(&:name)
      end

      def hidden_variables
        variables = []

        visible_variables.each do |variable|
          next if model.subject?(variable.name)
          next unless (model.parent_subject_names(variable.name) & subjects_by_variables).empty?

          variables << Variable.new(@config, closest_subject_name(variable.name))
        end

        variables.uniq(&:name)
      end

      def subject_by_variable(variable)
        if variable.property_path_exist?
          subject_by_property_path_variable(variable)
        else
          subject_by_object_name_normal(variable.name)
        end
      end

      def subject_by_property_path_variable(variable)
        object = model.find_object(variable.name)
        if object.is_a?(Model::Subject)
          subject = object
        elsif model.subject?(variable.name)
          subject_name = (model.parent_subject_names(object_name) & variables_for_where.map(&:name)).last
          subject = model.find_subject(subject_name)
        else
          object_names =
            (model.route_by_object_name(variable.name)[0..-2].map { |triple| triple.object.as_object_name } & visible_variables.map(&:name))
          subject = if object_names.empty?
                      model.find_one_by_object_name(variable.name).subject
                    else
                      model.find_object(object_names.last)
                    end
        end

        subject
      end

      def subject_by_object_name_normal(object_name)
        model.route_by_object_name(object_name).reverse.each_with_index do |triple, idx|
          if triple.object.is_a?(Model::Subject)
            as_object_name = triple.object.as_object_name
            return triple.object if idx.positive? && variables(@config.name).map(&:name).include?(as_object_name)
          end

          return triple.subject if variables(@config.name).map(&:name).include?(triple.subject.name)
        end

        triple = model.find_by_object_name(object_name)
        if triple.nil? || common_subject_names.nil? || common_subject_names.empty?
          model.subjects.first
        else
          parent_subject_names = model.parent_subject_names(object_name)
          commons_by_variables = parent_subject_names & variables(@config.name).map(&:name)
          if commons_by_variables.empty?
            subject_names = parent_subject_names & common_subject_names
            if subject_names.empty?
              model.subjects.first
            else
              model.find_subject(subject_names.last)
            end
          else
            model.find_subject(commons_by_variables.last)
          end
        end
      end

      def common_subject_names
        return @common_subject_names if @common_subject_names

        @common_subject_names = model.subjects.map(&:name)
        visible_variables.reject do |variable|
          model.subject?(variable.name) || variable.property_path_exist? || variable.subject_of_property_path?
        end.each do |variable|
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

      def variables_by_config
        return @variables_by_config unless @variables_by_config.nil?

        @variables_by_config = @config.sparql_variables(@sparql_name).map do |variable|
          variable_inst = Variable.new(@config, variable)
          if variable_inst.property_path_exist?
            [Variable.new(@config, variable_inst.property_path.subject, as_subject: true), variable_inst]
          else
            variable_inst
          end
        end.flatten
      end

      def parameters_by_config
        return @parameters_by_config unless @parameters_by_config.nil?

        begin
          @parameters_by_config = @config.sparql_parameters(@sparql_name).map do |name, value|
            Variable.new(@config, "#{name}=#{value}")
          end
          @parameters_by_config = [] if @parameters_by_config.nil?
        rescue StandardError
          @parameters_by_config = []
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

        @variables_by_config = nil
        @parameters_by_config = nil

        @variables_by_query_opts = {}
        @parameters_by_query_opts = {}
        @configs.each do |conf|
          @variables_by_query_opts[conf.name] = []
          @parameters_by_query_opts[conf.name] = []
        end

        @variables = {}
        @variables_for_where = {}

        parse_query_opts(opts[:query])
        set_variables
      end
    end
  end
end
