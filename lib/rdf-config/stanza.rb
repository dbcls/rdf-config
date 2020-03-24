require 'rdf-config/stanza/ruby'
require 'rdf-config/stanza/javascript'

class RDFConfig
  class Stanza
    def initialize(model, stanza_id = 'stanza')
      @model = model
      @metadata_config = @model.parse_stanza
      @sparql = SPARQL.new(@model)

      @name = @metadata_config.keys.at(0)
      mkdir unless File.exist?(output_dir)

      @stanza = @sparql.config(metadata['sparql'])
    end

    def metadata
      @metadata_config[@name]
    end

    def generate
      STDERR.puts "Generate stanza: #{@name}"

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

      lines << "{{#each #{@name}}}"
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

    def output_dir
      "#{metadata['output_dir']}/#{@stanza_type}"
    end

    def metadata_parameters
      metadata['parameters']
    end

    def stanza_parameters
      @stanza['parameters']
    end

    def variables
      @stanza['variables']
    end

    def mkdir
      FileUtils.mkdir_p(output_dir)
    end

    def output_metadata_json(metadata)
      File.open(metadata_json_fpath, 'w') do |f|
        f.puts JSON.pretty_generate(metadata)
      end
    end

    def metadata_json_fpath
      "#{@base_dir}/metadata.json"
    end
  end
end
