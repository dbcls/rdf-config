class RDFConfig

  class Stanza
    def initialize(config_dir)
      @config_dir = config_dir

      stanza_config_file = "#{config_dir}/stanza.yaml"
      @stanza_config = YAML.load_file(stanza_config_file)

      @name = @stanza_config.keys.at(0)

      @model = Model.new(config_dir)
      @sparql = SPARQL.new(config_dir)
    end

    def generate
      STDERR.puts "Generate stanza: #{@name}"

      mkdir unless File.exist?(output_dir)

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
      parameters = []

      arguments.each do |argument|
        parameters << {
            "#{prefix}key" => argument['key'],
            "#{prefix}example" => argument['example'],
            "#{prefix}description" => argument['description'],
            "#{prefix}required" => argument['required'],
        }
      end

      parameters
    end

    def sparql_result_html(suffix = '', indent_chars = '  ')
      lines = []

      lines << "{{#each #{@name}}}"
      lines << %(#{indent_chars}<dl class="dl-horizontal">)
      variables.each do |variable|
        lines << "#{indent_chars * 2}<dt>#{variable['label']}</dt><dd>{{#{variable['name']}#{suffix}}}</dd>"
      end
      lines << "#{indent_chars}</dl>"
      lines << '{{/each}}'

      lines.join("\n")
    end

    def sparql_query
      sparql_lines = []
      sparql_lines << @sparql.prefix_lines_for_sparql
      sparql_lines << %(SELECT #{variables.map { |variable| "?#{variable['name']}" }.join(' ')})
      sparql_lines << 'WHERE {'
      arguments.each do |argument|
        predicate = @model.property_path_map[argument['key']]
        object =
        sparql_lines << "  ?s #{predicate} #{object_value_by_argument(argument)} ."
      end
      variables.each do |variable|
        predicate = @model.property_path_map[variable['name']]
        object = "?#{variable['name']}"
        sparql_lines << "  ?s #{predicate} #{object} ."
      end
      sparql_lines << '}'

      sparql_lines.join("\n")
    end

    def output_dir
      @stanza_config[@name]['output_dir']
    end

    def stanza_version
      @stanza_config[@name]['stanza_version']
    end

    def arguments
      @stanza_config[@name]['arguments']
    end

    def variables
      @stanza_config[@name]['variables']
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

    class Ruby < Stanza
      def initialize(config_dir)
        super(config_dir)
        @base_dir = "#{output_dir}/#{@name}_stanza"
        @generate_template_cmd = "togostanza init #{output_dir}; cd #{output_dir}; togostanza stanza new #{@name}"
      end

      def generate
        generate_template
        update_metadata_json
        update_stanza_html
        update_stanza_rb
      end

      def update_metadata_json
        metadata = JSON.parse(File.read(metadata_json_fpath))
        metadata['parameter'] = parameters_for_metadata
        output_metadata_json(metadata)
      end

      def update_stanza_html
        indent_chars = ''
        lines = File.readlines(stanza_html_fpath)
        File.open(stanza_html_fpath, 'w') do |f|
          lines.each do |line|
            if /(\s*)<body>/ =~ line
              indent_chars = $1
              f.write line
              break
            end
            f.write line
          end

          f.puts sparql_result_html('', indent_chars)
          f.puts "#{indent_chars}</body>"
          f.puts '</html>'
        end
      end

      def update_stanza_rb
        lines = File.readlines(stanza_rb_fpath)
        File.open(stanza_rb_fpath, 'w') do |f|
          lines.each do |line|
            break if /\Aend/ =~ line
            f.write line
          end
          f.puts ''

          f.puts "  property :#{@name} do |#{arguments.map { |arg| arg['key'] }.join(', ')}|"
          f.puts "    query('#{@sparql.endpoint}', <<-SPARQL.strip_heredoc)"
          f.puts sparql_query
          f.puts '    SPARQL'
          f.puts '  end'
          f.puts 'end'
        end
      end

      def object_value_by_argument(argument)
        ['"#{', argument['key'], '}"'].join
      end

      def stanza_html_fpath
        "#{@base_dir}/template.hbs"
      end

      def stanza_rb_fpath
        "#{@base_dir}/stanza.rb"
      end
    end

    class JavaScript < Stanza
      def initialize(config_dir)
        super(config_dir)
        @base_dir = "#{output_dir}/#{@name}"
        @generate_template_cmd = "cd #{output_dir}; ts new #{@name}"
      end

      def generate
        generate_template
        update_index_js
        update_metadata_json
        update_stanza_html
        generate_stanza_rq
      end

      def update_index_js
        index_js = <<-EOS
Stanza(function(stanza, params) {
  var q = stanza.query({
    endpoint: "#{@sparql.endpoint}",
    template: "stanza.rq",
    parameters: params
  });

  q.then(function(data) {
    var rows = data.results.bindings;
    stanza.render({
      template: "stanza.html",
      parameters: {
        #{@name}: rows
      },
    });
  });
});
EOS
        File.open(index_js_fpath, 'w') do |f|
          f.write(index_js)
        end
      end

      def update_metadata_json
        stanza_parameters = parameters_for_metadata('stanza:')
        stanza_usages = []
        arguments.each do |argument|
          stanza_usages << { argument['key'] => argument['example'] }
        end
        stanza_usage_attr = stanza_usages.map do |usage|
          key = usage.keys.first
          %(#{key}="#{usage[key]}")
        end.join(' ')

        metadata = JSON.parse(File.read(metadata_json_fpath))
        metadata['stanza:parameter'] = stanza_parameters
        metadata['stanza:usage'] = "<togostanza-#{@name} #{stanza_usage_attr}></togostanza-#{@name}>"
        output_metadata_json(metadata)
      end

      def update_stanza_html
        File.open(stanza_html_fpath, 'w') do |f|
          f.puts sparql_result_html('.value')
        end
      end

      def generate_stanza_rq
        File.open(stanza_rq_fpath, 'w') do |f|
          f.puts sparql_query
        end
      end

      def object_value_by_argument(argument)
        %("{{#{argument['key']}}}")
      end

      def index_js_fpath
        "#{@base_dir}/index.js"
      end

      def stanza_html_fpath
        "#{@base_dir}/templates/stanza.html"
      end

      def stanza_rq_fpath
        "#{@base_dir}/templates/stanza.rq"
      end
    end
  end

end
