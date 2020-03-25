class RDFConfig
  class SPARQL
    require 'rdf-config/model/triple'

    attr_reader :variables

    def initialize(model, opts)
      if opts[:sparql_query_name].to_s.empty?
        query_name = 'sparql'
      else
        query_name = opts[:sparql_query_name]
      end

      @model = model

      @prefixes = model.prefix

      @sparql_config = model.parse_sparql

      if @sparql_config.key?(query_name)
        @parameters = @sparql_config[query_name].key?('parameters') ? @sparql_config[query_name]['parameters'] : {}
        @variables = @sparql_config[query_name]['variables']
      else
        raise "Error: No SPARQL query (#{query_name}) exists."
      end

      @endpoint_config = model.parse_endpoint
    end

    def generate
      sparql_lines = comment_lines

      sparql_lines += prefix_lines_for_sparql
      sparql_lines << ''
      sparql_lines << select_line
      sparql_lines << 'WHERE {'
      sparql_lines += values_lines
      sparql_lines += where_phase_lines(@variables)
      sparql_lines << '}'
      sparql_lines << 'LIMIT 100'

      sparql_lines.join("\n")
    end

    def run
      endpoint_uri = URI.parse(@endpoint)

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

    def comment_lines
      lines = []

      endpoints = all_endpoints.dup
      lines << "# Endpoint: #{endpoints.shift}"
      endpoints.each do |endpoint|
        lines << "#           #{endpoint}"
      end

      lines << "# Description: #{description}"

      first_parameter = true
      @parameters.each do |var_name, value|
        if first_parameter
          first_parameter = false
          s = '# Parameter: '
        else
          s = '#            '
        end
        lines << "#{s}#{var_name}: (example: #{value})"
      end
      lines << ''

      lines
    end

    def prefix_lines_for_sparql(variables = @variables, parameters = @parameters)
      prefixes = used_prefixes(variables, parameters)

      prefix_lines = []
      @prefixes.each do |prefix, uri|
        prefix_lines << "PREFIX #{prefix}: #{uri}" if prefixes.include?(prefix)
      end

      prefix_lines
    end

    def select_line
      %/SELECT #{select_var_names.map { |name| "?#{name}" }.join(' ')}/
    end

    def values_lines(parameters = @parameters)
      lines = []

      parameters.each do |var_name, value|
        if @model.object_type(var_name) == :literal
          value = %Q("#{value}")
        end
        lines << "  VALUES ?#{var_name} { #{value} }"
      end

      lines
    end

    def where_phase_lines(var_names)
      triple = @model.sparql_triple_lines(var_names)
      lines = []
      triple[:required].each do |subject_name, properties|
        next if properties.empty?

        if properties.size > 1
          first_line = properties.shift
          last_line = properties.pop
          lines << "  ?#{subject_name} #{first_line[0]} #{first_line[1]} ;"
          properties.each do |property|
            lines << "      #{property[0]} #{property[1]} ;"
          end
          lines << "      #{last_line[0]} #{last_line[1]} ."
        else
          lines << "  ?#{subject_name} #{first_line[0]} #{first_line[1]} ."
        end
      end

      triple[:optional].each do |subject_name, properties|
        properties.each do |property|
          lines << "  OPTIONAL { ?#{subject_name} #{property[0]} #{property[1]} . }"
        end
      end

      lines
    end

    def find_variable(var_name)
      var_info = {}
      @model.property_path_map.each do |subj_name, path_map|
        if path_map[var_name]
          var_info[:subject_name] = subj_name
          var_info[:path_map] = path_map[var_name]
          break
        end
      end

      var_info
    end

    def used_subject_names
      names = []
      @variables.each do |var_name|
        subject_name = @model.subject_name(var_name)
        names << subject_name unless names.include?(subject_name)
      end

      names
    end

    def select_var_names
      used_subject_names.reject { |name| @variables.include?(name) } + @variables
    end

    def used_prefixes(variables = @variables, parameters = @parameters)
      prefixes = @model.used_prefixes(variables)
      parameters.each do |var_name, value|
        next if @model.object_type(value) == :literal

        if /\A(\w+):(.+)/ =~ value && !prefixes.include?($1)
          prefixes << $1
        end
      end

      prefixes
    end

    def has_parameters?
      !@parameters.empty?
    end

    def description
      @sparql_config['sparql']['description'].to_s
    end

    def all_endpoints
      case @endpoint_config['endpoint']
      when String
        [@endpoint_config['endpoint']]
      when Array
        @endpoint_config['endpoint']
      end
    end

    def endpoint
      case @endpoint_config['endpoint']
      when String
        @endpoint_config['endpoint']
      when Array
        @endpoint_config['endpoint'].first
      end
    end

    def config(name)
      @sparql_config[name]
    end
  end

end
