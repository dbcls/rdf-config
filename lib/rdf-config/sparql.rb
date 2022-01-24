require 'rdf-config/model'
require 'rdf-config/sparql/sparql_generator'
require 'rdf-config/sparql/comment_generator'
require 'rdf-config/sparql/prefix_generator'
require 'rdf-config/sparql/select_generator'
require 'rdf-config/sparql/dataset_generator'
require 'rdf-config/sparql/where_generator'
require 'rdf-config/sparql/solution_modifier_generator'

class RDFConfig
  class SPARQL
    DEFAULT_NAME = 'sparql'.freeze
    OPTIONS_VALID_KEYS = %w[distinct order_by offset limit].freeze
    @@validate_done = false

    def initialize(config, opts = {})
      @config = config
      @opts = opts.merge(default_option)

      @errors = []
      @warnings = []

      @query_name = opts[:sparql_query_name].to_s.strip
      return if @query_name.empty?

      sparql_query_name, endpoint_name = @opts[:sparql_query_name].to_s.split(':')
      @opts[:sparql_query_name] = sparql_query_name.nil? ? DEFAULT_NAME : sparql_query_name
      @opts[:endpoint_name] = endpoint_name unless endpoint_name.nil?

      @values = opts[:values] || {}
      @variables = opts[:variables] if opts.key?(:variables)
      # @parameters = opts[:parameters] if opts.key?(:parameters)
      if !opts.key?(:check_query_name) || opts[:check_query_name] == true
        raise SPARQLConfigNotFound, "No SPARQL config found: sparql query name '#{name}'" unless @config.sparql.key?(name)
      end

      validate
      raise InvalidSPARQLConfig, %(ERROR:\n#{@errors.map { |msg| "  #{msg}" }.join("\n")}) if error?

      if @config.sparql[name].key?('options')
        @opts = @opts.merge(@config.sparql[name]['options'])
      end

      @subjects_by_variables = []
      variables.each do |variable_name|
        object = model.find_object(variable_name)
        @subjects_by_variables << object.name if object.is_a?(Model::Subject)
      end

      @variables_for_where = nil
      @common_subject_names = nil
    end

    def print_usage
      STDERR.puts 'Usage: --sparql query_name[:endpoint_name]'
      STDERR.puts "Available SPARQL query names: #{query_names.join(', ')}"
      with_parameter_configs = configs_having_parameters
      unless with_parameter_configs.empty?
        STDERR.puts "Available SPARQL query parameters:"
        with_parameter_configs.each do |query_name, config|
          case config['parameters']
          when Hash
            parameters = config['parameters'].keys.join(', ')
          when Array
            parameters = config['parameters'].join(', ')
          else
            parameters = config['parameters'].to_s
          end
          STDERR.puts "  #{query_name}: #{parameters}"
        end
      end
      STDERR.puts "Available SPARQL endpoint names: #{@config.endpoint.keys.join(', ')}"
    end

    def generate(opts = {})
      if @query_name.empty?
        print_usage
        return
      end

      validate
      output_warning_messages

      sparql_generator = SPARQLGenerator.new

      unless  opts[:url_encode]
        sparql_generator.add_generator(CommentGenerator.new(@config, @opts))
      end
      sparql_generator.add_generator(PrefixGenerator.new(@config, @opts))
      sparql_generator.add_generator(SelectGenerator.new(@config, @opts))
      sparql_generator.add_generator(DatasetGenerator.new(@config, @opts))
      sparql_generator.add_generator(WhereGenerator.new(@config, @opts))
      sparql_generator.add_generator(SolutionModifierGenerator.new(@config, @opts))

      if  opts[:url_encode]
        require 'uri'
        [endpoint, '?', URI.encode_www_form(query: sparql_generator.generate.join("\n"))].join
      else
        sparql_generator.generate.join("\n")
      end
    end

    def name
      @name = if @opts[:sparql_query_name].to_s.empty?
                DEFAULT_NAME
              else
                @opts[:sparql_query_name]
              end
    end

    def variables
      @variables ||=
        ((@config.sparql[name].key?('variables') ? @config.sparql[name]['variables'] : []) + parameters.keys).uniq
    end

    def options_hash
      @options ||=
        @config.sparql[name].key?('options') ? @config.sparql[name]['options'] : {}
    end

    def valid_variables
      valid_vs = []
      variables.each do |variable_name|
        if model.subject?(variable_name)
          valid_vs << variable_name
        else
          triple = model.find_by_object_name(variable_name)
          valid_vs << variable_name unless triple.nil?
        end
      end

      valid_vs
    end

    def parameters
      @parameters ||=
        @config.sparql[name].key?('parameters') ? @config.sparql[name]['parameters'] : {}
    end

    def description
      @description ||=
        @config.sparql[name].key?('description') ? @config.sparql[name]['description'] : ''
    end

    def endpoints
      endpoint_opts = if @opts.key?(:endpoint_name)
                        { name: @opts[:endpoint_name] }
                      else
                        {}
                      end
      @endpoint ||= Endpoint.new(@config, endpoint_opts)
      @endpoint.endpoints
    rescue
      []
    end

    def endpoint
      endpoints.first
    end

    def namespace
      @namespace ||= @config.prefix
    end

    def model
      @model ||= Model.new(@config)
    end

    def variable_name_for_sparql(variable_name, add_question_mark = false)
      if !variable_name.empty? && add_question_mark
        "?#{variable_name}"
      else
        variable_name.to_s
      end
    end

    def subject_by_object_name(object_name)
      model.triples_by_object_name(object_name).reverse.each_with_index do |triple, idx|
        begin
          as_object_name = triple.object.as_object_name
        rescue
          as_object_name = ''
        end

        if idx > 0 && variables.include?(as_object_name)
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

    def closest_subject(object_name)
      parent_subject_names = model.parent_subject_names(object_name)
      object_name_for_subject = nil
      parent_subject_names.reverse.each do |subject_name|
        if @subjects_by_variables.include?(subject_name)
          object_name_for_subject = subject_name
          break
        end
      end

      if object_name_for_subject.nil?
        model.find_subject(parent_subject_names.first)
      else
        model.find_subject(object_name_for_subject)
      end
    end

    def common_subject_names
      if @common_subject_names.nil?
        variables_for_where.each do |variable_name|
          next if model.subject?(variable_name)

          triple = model.find_by_object_name(variable_name)
          next if triple.nil? || variables.include?(triple.subject.name)

          if @common_subject_names.nil?
            @common_subject_names = model.parent_subject_names(variable_name)
          else
            @common_subject_names &= model.parent_subject_names(variable_name)
          end
        end

        @common_subject_names = [] if @common_subject_names.nil?
      end

      @common_subject_names
    end

    def hidden_variables
      variable_names = []

      variables.each do |variable_name|
        next if model.subject?(variable_name)

        subject = closest_subject(variable_name)
        variable_names << subject.name if !subject.nil? && !variables.include?(subject.name)
      end

      parameters.keys.each do |variable_name|
        variable_names << variable_name
      end

      variable_names.flatten.uniq
    end

    def variables_for_where
      @variables_for_where ||= (variables + hidden_variables).uniq
    end

    def validate
      return if @@validate_done

      validate_options
      validate_variables
      @@validate_done = true
    end

    def add_error(error_message)
      @errors << error_message
    end

    def error?
      !@errors.empty?
    end

    def add_warning(warn_message)
      @warnings << warn_message
    end

    def output_warning_messages
      unless @warnings.empty?
        STDERR.puts @warnings.map { |msg| "WARNING: #{msg}" }.join("\n")
      end
    end

    def distinct?
      if @opts.key?('distinct') && @opts['distinct'] == true
        true
      else
        false
      end
    end

    def limit
      if @opts.key?('limit') && @opts['limit']
        @opts['limit']
      else
        nil
      end
    end

    def offset
      if @opts.key?('offset') && @opts['offset'].is_a?(Integer) && @opts['offset'] > 0
        @opts['offset']
      else
        nil
      end
    end

    def order_by
      if @opts.key?('order_by') && @opts['order_by']
        @opts['order_by']
      else
        nil
      end
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

    class SPARQLConfigNotFound < StandardError; end
    class InvalidSPARQLConfig < StandardError; end

    private

    def validate_variables
      variables.each do |variable_name|
        next if model.subject?(variable_name) || !model.find_object(variable_name).nil?

        add_warning("Variable name (#{variable_name}) is set in sparql.yaml file, but not in model.yaml file.")
      end
    end

    def validate_options
      return if options_hash.empty?

      validate_options_key
      validate_distinct
      validate_order_by
      validate_offset
      validate_limit
    end

    def validate_options_key
      invalid_keys = options_hash.keys - OPTIONS_VALID_KEYS
      unless invalid_keys.empty?
        add_error(%(Invalid options #{invalid_keys.map { |key| "'#{key}'" }.join(', ')} in sparql.yaml file. Valid options are #{OPTIONS_VALID_KEYS.join(', ')}.))
      end
    end

    def validate_order_by
      case options_hash['order_by']
      when String
        validate_order_by_variable_name(options_hash['order_by'])
      when Hash
        options_hash['order_by'].keys.each do |variable_name|
          validate_order_by_variable_name(variable_name)
        end
        options_hash['order_by'].each do |variable_name, value|
          next if %w[ASC DESC].include?(value.upcase)

          add_error("The value of order_by '#{variable_name}' in sparql.yaml file must be either asc or desc.")
        end
      when Array
        options_hash['order_by'].each do |item|
          case item
          when String
            validate_order_by_variable_name(item)
          when Hash
            validate_order_by_variable_name(item.keys.first)
          end
        end
      end
    end

    def validate_order_by_variable_name(variable_name)
      unless variables.include?(variable_name)
        add_error(invalid_order_by_message(variable_name))
      end
    end

    def invalid_order_by_message(variable_name)
      "Variable name '#{variable_name}' is set order_by option, but it is not contained in the variables."
    end

    def validate_distinct
      return unless options_hash.key?('distinct')

      unless [TrueClass, FalseClass].include?(options_hash['distinct'].class)
        add_error("The value of option 'distinct' in sparql.yaml file must be either true or false.")
      end
    end

    def validate_offset
      return unless options_hash.key?('offset')

      unless options_hash['offset'].is_a?(Integer)
        add_error("The value of option 'offset' in sparql.yaml file must be an integer.")
      end
    end

    def validate_limit
      return if options_hash.key?('limit')

      if options_hash['limit'] != false && options_hash['limit'].is_a?(Integer)
        add_error("The value of option 'limit' in sparql.yaml file must be an integer.")
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
  end
end
