require 'rdf-config/model'
require 'rdf-config/sparql/validator'
require 'rdf-config/sparql/sparql_generator'
require 'rdf-config/sparql/comment_generator'
require 'rdf-config/sparql/prefix_generator'
require 'rdf-config/sparql/select_generator'
require 'rdf-config/sparql/dataset_generator'
require 'rdf-config/sparql/where_generator'
require 'rdf-config/sparql/solution_modifier_generator'
require 'rdf-config/sparql/variables_handler'

class RDFConfig
  class SPARQLConfigNotFound < StandardError; end
  class InvalidSPARQLConfig < StandardError; end

  class SPARQL
    OPTIONS_VALID_KEYS = %w[distinct order_by offset limit].freeze

    def initialize(config, opts = {})
      if config.is_a?(Array)
        @configs = config
        @config = config.first
      else
        @configs = [config]
        @config = config
      end
      @opts = default_option.merge(opts)
      @opts[:query_name] = opts[:sparql]
      @opts[:join] = [@opts[:join]] if @opts.key?(:join) && @opts[:join].is_a?(String)

      @values = {}
      @namespaces = {}

      parse_opts

      return if print_usage?

      if (!@opts.key?(:check_query_name) || @opts[:check_query_name]) && sparql? && !@config.sparql.key?(name)
        raise SPARQLConfigNotFound, "ERROR: SPARQL config not found: sparql query name '#{name}'"
      end

      merge_options_config
    end

    def generate(opts = {})
      @validator = RDFConfig::SPARQL::Validator.instance(@config, @opts)
      @validator.validate

      sparql_lines = generate_sparql_lines
      if opts[:url_encode]
        require 'uri'
        [endpoint, '?', URI.encode_www_form(query: sparql_lines.join("\n"))].join
      else
        sparql_lines.join("\n")
      end
    end

    def generate_sparql_lines
      sparql_generator = SPARQLGenerator.new

      sparql_generator.add_generator(CommentGenerator.new(@config, @opts)) if sparql_comment?
      sparql_generator.add_generator(PrefixGenerator.new(@configs, @opts))
      sparql_generator.add_generator(SelectGenerator.new(@configs, @opts))
      sparql_generator.add_generator(DatasetGenerator.new(@configs, @opts))
      sparql_generator.add_generator(WhereGenerator.new(@configs, @opts))
      sparql_generator.add_generator(SolutionModifierGenerator.new(@config, @opts)) unless template?

      sparql_generator.generate
    end

    def print_usage?
      empty_sparql_option? || empty_query_option? || empty_endpoint_option?
    end

    def print_usage
      print_sparql_usage if empty_sparql_option?
      print_query_usage if empty_query_option?
      print_endpoint_usage if empty_endpoint_option?
      warn_available_endpoint_names
    end

    def print_warnings
      model.print_warnings
      @validator.output_warning_messages
    end

    def config_name
      @config.name
    end

    def name
      @opts[:query_name]
    end

    def variables
      variables_handler.variables(config_name)
    end

    def valid_variable(variable_name)
      variables_handler.valid_variable(variable_name)
    end

    def parameters
      @parameters ||= variables_handler.parameters
    end

    def description
      @description ||= if sparql?
                         @config.sparql[name].key?('description') ? @config.sparql[name]['description'] : ''
                       else
                         ''
                       end
    end

    def options
      @options ||= if sparql?
                     @config.sparql[name].key?('options') ? @config.sparql[name]['options'] : {}
                   else
                     {}
                   end
    end

    def endpoints
      endpoint_opts = if @opts.key?(:endpoint_name)
                        { name: @opts[:endpoint_name] }
                      else
                        {}
                      end
      @endpoint ||= Endpoint.new(@config, endpoint_opts)
      @endpoint.endpoints
    rescue StandardError
      []
    end

    def endpoint
      endpoints.first
    end

    def namespace
      @namespaces[@config.name] = @config.prefix unless @namespaces.key?(@config.name)

      @namespaces[@config.name]
    end

    def variable_name_for_sparql(variable_name, add_question_mark = false)
      return '' if variable_name.empty?

      name = if join?
               "#{config_name}__#{variable_name}"
             else
               variable_name
             end
      name = "?#{name}" if add_question_mark

      name
    end

    def subject_by_object_name_new(object_name)
      variables_handler.subject_by_object_name(object_name)
    end

    def subject_by_object_name(object_name)
      model.triples_by_object_name(object_name).reverse.each_with_index do |triple, idx|
        begin
          as_object_name = triple.object.as_object_name
        rescue StandardError
          as_object_name = ''
        end

        if idx.positive? && variables.include?(as_object_name)
          return triple.object
        elsif variables.include?(triple.subject.name)
          return triple.subject
        end
      end

      triple = model.find_by_object_name(object_name)
      if triple.nil? || common_subject_names.nil? || common_subject_names.empty?
        model.subjects.first
      else
        parent_subject_names = model.parent_subject_names(object_name)
        commons_by_variables = parent_subject_names & variables
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
      variables_handler.common_subject_names
    end

    def variables_for_where
      variables_handler.variables_for_where
    end

    def variables_for_where_bak
      unless @variables_for_where.key?(config_name)
        @variables_for_where[config_name] = variables_handler.variables_for_where
      end

      @variables_for_where[config_name]
    end

    def distinct?
      if @opts.key?('distinct') && @opts['distinct'] == true
        true
      else
        false
      end
    end

    def limit
      @opts['limit'] if @opts.key?('limit') && @opts['limit']
    end

    def offset
      @opts['offset'] if @opts.key?('offset') && @opts['offset'].is_a?(Integer) && (@opts['offset']).positive?
    end

    def order_by
      @opts['order_by'] if @opts.key?('order_by') && @opts['order_by']
    end

    def run
      endpoint_uri = URI.parse(endpoint)

      sparql_query = generate
      puts sparql_query

      http = Net::HTTP.new(endpoint_uri.host, endpoint_uri.port)
      http.use_ssl = endpoint_uri.scheme == 'https'
      headers = {
        'Accept' => 'application/sparql-results+json',
        'Content-Type' => 'application/x-www-form-urlencoded'
      }

      url_path = endpoint_uri.path
      url_query = URI.encode_www_form({query: sparql_query})
      response = http.get("#{url_path}?#{url_query}", headers)
      case response.code
      when '200'
        pp JSON.parse(response.body)
      else
        puts response.body
      end
    end

    private

    def init_instance_variables
      @variables_hash = nil
      @parameters = nil
      @description = nil
      @options = nil
      @endpoint = nil
    end

    def parse_opts
      sparql_argv = if @opts[:sparql].is_a?(Array)
                      @opts[:sparql].first
                    else
                      @opts[:sparql]
                    end
      sparql_argv = sparql_argv.to_s.strip

      @opts[:query_name] = sparql_argv
      set_query_opts if @opts.key?(:query)
    end

    def set_query_opts
      if @opts[:query].is_a?(String)
        @opts[:query] = if @opts[:query].strip.empty?
                          []
                        else
                          [@opts[:query]]
                        end
      end

      @opts[:query].each do |var_val|
        variable_name, value = var_val.split('=', 2)
        @values[variable_name] = value if value
      end
    end

    def variables_by_parameters_config
      parameters.keys
    end

    def variables_by_variables_config
      @config.sparql[name].key?('variables') ? @config.sparql[name]['variables'] : []
    end

    def variables_by_sparql_args
      @values.keys
    end

    def subjects_by_variables
      variables_handler.visible_variables.select do |variable_name|
        model.find_object(variable_name).is_a?(Model::Subject)
      end
    end

    def default_option
      {
        'distinct' => false,
        'limit' => 100,
        'offset' => nil,
        'order_by' => nil
      }
    end

    def merge_options_config
      @opts = @opts.merge(@config.sparql[name]['options']) if sparql? && @config.sparql[name].key?('options')
    end

    def query_names
      if @config.sparql.is_a?(Hash)
        @config.sparql.keys
      else
        []
      end
    end

    def configs_having_parameters
      @config.sparql.select do |query_name, config_hash|
        config_hash.is_a?(Hash) && config_hash.key?('parameters')
      end
    end

    def sparql?
      @opts.key?(:sparql)
    end

    def query?
      @opts.key?(:query)
    end

    def join?
      @opts.key?(:join)
    end

    def config_by_name(config_name)
      @configs.select { |config| config.name == config_name }.first
    end

    def model
      Model.instance(@config)
    end

    def variables_handler
      VariablesHandler.instance(@config, @opts)
    end

    def print_sparql_usage
      warn 'Usage: --sparql query_name [--query var=value] [--endpoint endpoint_name]'
      warn "Available SPARQL query names: #{query_names.join(', ')}"
      with_parameter_configs = configs_having_parameters
      unless with_parameter_configs.empty?
        warn 'Preset SPARQL query parameters (use --query to override):'
        with_parameter_configs.each do |query_name, config|
          parameters = case config['parameters']
                       when Hash
                         config['parameters'].keys.join(', ')
                       when Array
                         config['parameters'].join(', ')
                       else
                         config['parameters'].to_s
                       end
          warn "  #{query_name}: #{parameters}"
        end
      end
    end

    def print_query_usage
      warn 'Usage: --query var1 var2=value var3 [--endpoint endpoint_name]'
      warn '  var: Specify a list of variable names (defined in the model.yaml file).'
      warn '  var=value: Specify variable name and its value to be assigned.'
    end

    def print_endpoint_usage
      warn 'Usage: --endpoint endpoint_name'
    end

    def warn_available_endpoint_names
      warn "Available SPARQL endpoint names: #{@config.endpoint.keys.join(', ')}"
    end

    def sparql_name?
      (name.to_s.empty? && !@opts.key?(:query)) ||
        (@opts.key?(:endpoint_name) && @opts[:endpoint_name].to_s.strip.empty?)
    end

    def empty_sparql_option?
      @opts.key?(:sparql) && @opts[:sparql].to_s.strip.empty?
    end

    def empty_query_option?
      @opts.key?(:query) && @opts[:query].empty?
    end

    def empty_endpoint_option?
      @opts.key?(:endpoint_name) && @opts[:endpoint_name].to_s.strip.empty?
    end

    def sparql_comment?
      if @opts.key?(:sparql_comment)
        @opts[:sparql_comment]
      else
        true
      end
    end

    def template?
      if @opts.key?(:template)
        @opts[:template]
      else
        false
      end
    end

    def select_variables(add_question_mark: false)
      if join?
        valid_variables_by_query(add_question_mark)
      else
        variables_handler.variables_for_select.map { |name| variable_name_for_sparql(name, add_question_mark) }
      end
    end

    def valid_variables_by_query(add_question_mark: false)
      variable_names = []
      @opts[:query].each do |query|
        config_name, variable_name = query.split(':')
        @config = @configs.select { |config| config.name == config_name }.first
        name = valid_variable(variable_name)
        variable_names << variable_name_for_sparql(name, add_question_mark) unless name.nil?
      end

      variable_names.uniq
    end
  end
end
