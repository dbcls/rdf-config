require 'fileutils'
require 'rdf-config/sparql/sparql_generator'
require 'rdf-config/stanza/javascript'
require 'rdf-config/stanza/ruby'

class RDFConfig
  class Stanza
    def initialize(config, opts = {})
      @config = config

      stanza_name = opts[:stanza_name].to_s
      if stanza_name.empty?
        @targets = config.stanza.keys
      else
        raise StanzaConfigNotFound, "No stanza config found: stanza name '#{stanza_name}'" unless config.stanza.key?(stanza_name)
        @targets = [stanza_name]
      end
    end

    def generate
      before_generate
      @targets.each do |stanza_name|
        @name = stanza_name
        generate_one_stanza
      end
      after_generate
    end

    def generate_one_stanza
      mkdir(stanza_base_dir) unless File.exist?(stanza_base_dir)
      STDERR.puts "Generate stanza: #{@name}"

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
            "#{prefix}required" => parameter['required'],
        }
      end

      params
    end

    def sparql_query
      sparql_generator = SPARQL::SPARQLGenerator.new

      sparql_generator.add_generator(sparql_prefix_generator)
      sparql_generator.add_generator(sparql_select_generator)
      sparql_generator.add_generator(sparql_where_generator)

      sparql_generator.generate.join("\n")
    end

    def sparql_result_html(suffix = '', indent_chars = '  ')
      lines = []

      lines << "{{#each #{@name}}}"
      lines << %(#{indent_chars}<dl class="dl-horizontal">)
      sparql.variables.each do |var_name|
        lines << "#{indent_chars * 2}<dt>#{var_name}</dt><dd>{{#{var_name}#{suffix}}}</dd>"
      end
      lines << "#{indent_chars}</dl>"
      lines << '{{/each}}'

      lines.join("\n")
    end

    def sparql
      @sparql ||= SPARQL.new(@config, sparql_query_name: stanza_conf['sparql'])
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
      STDERR.puts 'Stanza template has been generated successfully.'
    end

    def stanza_conf
      @stanza ||= @config.stanza[@name]
    end

    def sparql_prefix_generator
      @sparql_prefix_generator = SPARQL::PrefixGenerator.new(
          @config, sparql_query_name: stanza_conf['sparql']
      )
    end

    def sparql_select_generator
      @sparql_select_generator = SPARQL::SelectGenerator.new(
          @config, sparql_query_name: stanza_conf['sparql']
      )
    end

    def sparql_where_generator
      @sparql_select_generator = SPARQL::WhereGenerator.new(
          @config,
          sparql_query_name: stanza_conf['sparql'], template: true
      )
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

    class StanzaConfigNotFound < StandardError; end
    class StanzaExecutionFailure < StandardError; end
  end
end
