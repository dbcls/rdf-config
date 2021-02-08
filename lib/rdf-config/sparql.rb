require 'rdf-config/model'
require 'rdf-config/sparql/sparql_generator'
require 'rdf-config/sparql/comment_generator'
require 'rdf-config/sparql/prefix_generator'
require 'rdf-config/sparql/select_generator'
require 'rdf-config/sparql/dataset_generator'
require 'rdf-config/sparql/where_generator'

class RDFConfig
  class SPARQL
    DEFAULT_NAME = 'sparql'.freeze

    attr_accessor :offset, :limit

    def initialize(config, opts = {})
      @config = config
      @opts = opts

      sparql_query_name, endpoint_name = @opts[:sparql_query_name].to_s.split(':')
      @opts[:sparql_query_name] = sparql_query_name.nil? ? DEFAULT_NAME : sparql_query_name
      @opts[:endpoint_name] = endpoint_name unless endpoint_name.nil?

      @variables = opts[:variables] if opts.key?(:variables)
      @parameters = opts[:parameters] if opts.key?(:parameters)
      if !opts.key?(:check_query_name) || opts[:check_query_name] == true
        raise SPARQLConfigNotFound, "No SPARQL config found: sparql query name '#{name}'" unless @config.sparql.key?(name)
      end

      @subjects_by_variables = []
      variables.each do |variable_name|
        object = model.find_object(variable_name)
        if object.is_a?(Model::Subject)
          @subjects_by_variables << object.name
        end
      end

      @warnings = []
    end

    def generate
      validate
      output_warning_messages

      sparql_generator = SPARQLGenerator.new

      sparql_generator.add_generator(CommentGenerator.new(@config, @opts))
      sparql_generator.add_generator(PrefixGenerator.new(@config, @opts))
      sparql_generator.add_generator(SelectGenerator.new(@config, @opts))
      sparql_generator.add_generator(DatasetGenerator.new(@config, @opts))
      sparql_generator.add_generator(WhereGenerator.new(@config, @opts))

      sparql_generator.generate.join("\n")
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
        @config.sparql[name].key?('variables') ? @config.sparql[name]['variables'] : []
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
      begin
        if @opts.key?(:endpoint_name)
          endpoint_opts = { name: @opts[:endpoint_name] }
        else
          endpoint_opts = {}
        end
        @endpoint ||= Endpoint.new(@config, endpoint_opts)
        @endpoint.endpoints
      rescue
        []
      end
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

    def hidden_variables
      variable_names = []
      variables.each do |variable_name|
        next if model.subject?(variable_name)

        subject = subject_by_object_name(variable_name)
        variable_names << subject.name unless subject.nil?
      end

      parameters.keys.each do |variable_name|
        variable_names << variable_name
      end

      variable_names.flatten.uniq
    end

    def variables_for_where
      (variables + hidden_variables).uniq
    end

    def validate
      variables.each do |variable_name|
        next if model.subject?(variable_name) || !model.find_object(variable_name).nil?

        add_warning(%Q/Variable name (#{variable_name}) is set in sparql.yaml file, but not in model.yaml file./)
      end
    end

    def add_warning(warn_message)
      @warnings << warn_message
    end

    def output_warning_messages
      unless @warnings.empty?
        STDERR.puts @warnings.map { |msg| "WARNING: #{msg}" }.join("\n")
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
  end
end
