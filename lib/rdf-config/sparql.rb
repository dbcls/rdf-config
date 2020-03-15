class RDFConfig

  class SPARQL
    attr_reader :endpoint, :variables

    def initialize(config_dir)
      @config_dir = config_dir

      load_config_files
    end

    def load_config_files
      @model = Model.new(@config_dir)

      sparql_config_file = "#{@config_dir}/sparql.yaml"
      @sparql_config = YAML.load_file(sparql_config_file)

      endpoint_config_file = "#{@config_dir}/endpoint.yaml"
      @endpoint_config = YAML.load_file(endpoint_config_file)

      prefixes_config_file = "#{@config_dir}/prefix.yaml"
      @prefixes_config = YAML.load_file(prefixes_config_file)

      @endpoint = @endpoint_config['endpoint']
      @variables = @sparql_config['sparql']['variables']
    end

    def generate
      sparql_lines = []
      sparql_lines << prefix_lines_for_sparql
      sparql_lines << ''
      sparql_lines << %(SELECT ?s #{@variables.map { |var_name| "?#{var_name}" }.join(' ')})
      sparql_lines << 'WHERE {'
      sparql_lines << "  ?s a #{@model.model_type_map[subject_name]} ."
      @variables.each do |var_name|
        if @model.property_path_map[subject_name][var_name]
          sparql_lines << "  ?s #{@model.property_path_map[subject_name][var_name]} ?#{var_name} ."
        else
          var_info = find_variable(var_name)
          property_path = "#{@model.property_path_map[subject_name][var_info[:subject_name]]} / #{var_info[:path_map]}"
          sparql_lines << "  ?s #{property_path} ?#{var_name} ."
        end
      end
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
        JSON.parse(response.body)
      else
        response.body
      end
    end

    def prefix_lines_for_sparql
      prefix_lines = []
      @prefixes_config.each do |prefix, uri|
        prefix_lines << "PREFIX #{prefix}: #{uri}"
      end

      prefix_lines.join("\n")
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

    def subject_name
      @sparql_config['sparql']['subject']
    end
  end

end
