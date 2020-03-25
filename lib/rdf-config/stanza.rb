require 'rdf-config/stanza/ruby'
require 'rdf-config/stanza/javascript'

class RDFConfig
  class Stanza
    def initialize(model, opts = {})
      if opts[:stanza_name].to_s.empty?
        @stanza_name = 'stanza'
      else
        @stanza_name = opts[:stanza_name]
      end

      @model = model
      @stanza_config = @model.parse_stanza

      if @stanza_config.key?(@stanza_name)
        @sparql = SPARQL.new(@model, :sparql_query_name => current_stanza['sparql'])
        @stanza_base_dir = "#{current_stanza['output_dir']}/#{@stanza_type}"
        @stanza_dir = "#{@stanza_base_dir}/#{@stanza_name}"
        mkdir(@stanza_dir) unless File.exist?(@stanza_dir)
      else
        raise "Error: No Stanza config (#{@stanza_name}) exists."
      end
    end

    def current_stanza
      @stanza_config[@stanza_name]
    end

    def generate
      STDERR.puts "Generate stanza: #{@stanza_name}"

      case stanza_version
      when 'ruby'
        Ruby.new(@config_dir).generate
      when 'javascript'
        JavaScript.new(@config_dir).generate
      else
      end
    end

    def generate_template
      stdout, stderr, status = Open3.capture3("#{@generate_template_cmd}")

      if status.success?
        STDERR.puts 'Stanza template has been generated successfully.'
        case @stanza_type
        when 'javascript'
          STDERR.puts "To view the stanza, run (cd #{@stanza_base_dir}; ts server) and open http://localhost:8080/"
        when 'ruby'
          STDERR.puts "To view the stanza, run (cd #{@stanza_base_dir}; bundle exec rackup) and open http://localhost:9292/"
        end
        #puts stdout
        #puts stderr
      else
        STDERR.puts 'Generating stanza template failed.'
        STDERR.puts stderr
      end
    end

    def parameters_for_metadata(prefix = '')
      params = []

      metadata_parameters.each do |key, parameter|
        params << {
            "#{prefix}key" => key,
            "#{prefix}example" => parameter['example'],
            "#{prefix}description" => parameter['description'],
            "#{prefix}required" => parameter['required'],
        }
      end

      params
    end

    def sparql_result_html(suffix = '', indent_chars = '  ')
      lines = []

      lines << "{{#each #{@stanza_name}}}"
      lines << %(#{indent_chars}<dl class="dl-horizontal">)
      variables.each do |var_name|
        lines << "#{indent_chars * 2}<dt>#{var_name}</dt><dd>{{#{var_name}#{suffix}}}</dd>"
      end
      lines << "#{indent_chars}</dl>"
      lines << '{{/each}}'

      lines.join("\n")
    end

    def sparql_query
      sparql_lines = @sparql.prefix_lines_for_sparql(variables, stanza_parameters)
      sparql_lines << ''
      sparql_lines << %(SELECT #{variables.map { |variable| "?#{variable}" }.join(' ')})
      sparql_lines << 'WHERE {'
      sparql_lines += sparql_where_lines
      sparql_lines << '}'

      sparql_lines.join("\n")
    end

    def sparql_where_lines
      lines = @sparql.values_lines(sparql_hbs_parameters)
      lines += @sparql.where_phase_lines(variables)

      lines
    end

    def sparql_hbs_parameters
      params = {}
      stanza_parameters.keys.each do |var_name|
        params[var_name] = %({{#{var_name}}})
      end

      params
    end

    def metadata_parameters
      current_stanza['parameters']
    end

    def stanza_parameters
      @sparql.parameters
    end

    def variables
      @sparql.variables
    end

    def mkdir(dir)
      FileUtils.mkdir_p(dir)
    end

    def output_metadata_json(metadata)
      File.open(metadata_json_fpath, 'w') do |f|
        f.puts JSON.pretty_generate(metadata)
      end
    end

    def metadata_json_fpath
      "#{@stanza_dir}/metadata.json"
    end
  end
end
