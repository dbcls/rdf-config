require 'fileutils'
require 'rdf-config/sparql'
require 'rdf-config/sparql/validator'
require 'rdf-config/stanza/javascript'
require 'rdf-config/stanza/ruby'

class RDFConfig
  class Stanza
    YAML_SPARQL_KEY = 'sparql'.freeze
    attr_reader :sparql

    def initialize(config, opts = {})
      @config = config
      @opts = opts

      @stanza_name = opts[:stanza_name].to_s
      if @stanza_name.empty?
        @targets = config.stanza.keys
      else
        unless config.stanza.key?(@stanza_name)
          raise StanzaConfigNotFound, "ERROR: No stanza config found: stanza name '#{@stanza_name}'"
        end

        @name = @stanza_name
        @targets = [@stanza_name]
      end

      @sparql ||= SPARQL.new(@config, opts_for_initialize_sparql)
      validator = RDFConfig::SPARQL::Validator.instance(@config, opts_for_initialize_sparql)
      validator.validate
    end

    def print_usage
      warn 'Usage: --stanza stanza_name'
      warn "Available stanza names: #{@config.stanza.keys.join(', ')}"
    end

    def generate
      if @stanza_name.empty?
        print_usage
        return
      end

      before_generate
      @targets.each do |stanza_name|
        @name = stanza_name
        generate_one_stanza
      end
      after_generate
    end

    def generate_one_stanza
      mkdir(stanza_base_dir) unless File.exist?(stanza_base_dir)
      warn "Generate stanza: #{@name}"

      generate_template
      update_metadata_json
      update_stanza_html
      generate_sparql
      generate_versionspecific_files
    end

    def output_metadata_json(metadata)
      output_to_file(metadata_json_fpath, JSON.pretty_generate(metadata))
    end

    def update_metadata_json
      output_metadata_json(metadata_hash)
    end

    def update_stanza_html
      output_to_file(stanza_html_fpath, stanza_html)
    end

    def generate_sparql
      output_to_file(sparql_fpath, sparql_query)
    end

    def metadata_hash(prefix = '')
      metadata = {}

      metadata["#{prefix}parameter"] = parameters_for_metadata(prefix)
      metadata["#{prefix}label"] = label
      metadata["#{prefix}definition"] = definition

      metadata
    end

    def parameters_for_metadata(prefix = '')
      params = []

      parameters.each do |key, parameter|
        params << {
          "#{prefix}key" => key,
          "#{prefix}example" => parameter['example'],
          "#{prefix}description" => parameter['description'],
          "#{prefix}required" => parameter['required']
        }
      end

      params
    end

    def sparql_query
      sparql.generate
    end

    def sparql_result_html(suffix = '', indent_chars = '  ')
      lines = ["{{#each #{@name}}}"]

      unless parameters.empty?
        first_parameter_name = parameters.keys.first
        lines << '<p class="greeting">'
        lines << "#{first_parameter_name}: {{#{first_parameter_name}.value}}"
        lines << '</p>'
      end

      sparql.variables.each do |var_name|
        lines << '<dl>'
        lines << "#{indent_chars}<dt>#{var_name}</dt>"
        lines << "#{indent_chars}<dd>{{#{var_name}.value}}</dd>"
        lines << '</dl>'
      end
      lines << '{{/each}}'

      lines.join("\n")
    end

    def output_dir
      stanza_conf['output_dir']
    end

    def label
      stanza_conf['label']
    end

    def definition
      stanza_conf['definition']
    end

    def parameters
      stanza_conf['parameters']
    end

    private

    def before_generate; end

    def after_generate
      warn 'Stanza template has been generated successfully.'
    end

    def stanza_conf
      @stanza_conf ||= @config.stanza[@name]
    end

    def sparql_name
      stanza_conf[YAML_SPARQL_KEY]
    end

    def sparql_conf
      @sparql_conf ||= @config.sparql[sparql_name]
    end

    def mkdir(dir)
      FileUtils.mkdir_p(dir)
    end

    def output_to_file(fpath, data)
      File.open(fpath, 'w') do |f|
        f.puts data
      end
    end

    def stanza_base_dir
      "#{output_dir}/#{@stanza_type}"
    end

    def stanza_dir
      "#{stanza_base_dir}/#{@name}"
    end

    def metadata_json_fpath
      "#{stanza_dir}/metadata.json"
    end

    def opts_for_initialize_sparql
      @opts.merge(
        sparql: sparql_name,
        template: true,
        sparql_comment: false
      )
    end

    class StanzaConfigNotFound < StandardError; end
    class StanzaExecutionFailure < StandardError; end
  end
end
