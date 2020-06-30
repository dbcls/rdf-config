require 'open3'

class RDFConfig
  class Stanza
    class JavaScript < Stanza
      def initialize(config, opts = {})
        @stanza_type = 'javascript'

        super
      end

      def generate_template
        Dir.chdir(stanza_base_dir) do
          stdout, stderr, status = Open3.capture3("ts new #{@name}")
          unless  status.success?
            raise StanzaExecutionFailure, "ERROR: Stanza files creation failed.\n#{stderr}"
          end
        end

      rescue Errno::ENOENT => e
        raise StanzaExecutionFailure, "#{e.message}\nMake sure ts command is installed or ts command path is set in your PATH environment variable."
      end

      def generate_versionspecific_files
        update_index_js
      end

      def update_index_js
        output_to_file(index_js_fpath, index_js)
      end

      def metadata_hash
        stanza_usages = []
        parameters.each do |key, parameter|
          stanza_usages << { key => parameter['example'] }
        end
        stanza_usage_attr = stanza_usages.map do |usage|
          key = usage.keys.first
          %(#{key}="#{usage[key]}")
        end.join(' ')

        metadata = JSON.parse(File.read(metadata_json_fpath))
        metadata['stanza:usage'] = "<togostanza-#{@name} #{stanza_usage_attr}></togostanza-#{@name}>"

        metadata.merge(super('stanza:'))
      end

      def stanza_html
        sparql_result_html('.value')
      end

      def index_js
        <<-EOS
Stanza(function(stanza, params) {
  var q = stanza.query({
    endpoint: "#{sparql.endpoint}",
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
      end

      def after_generate
        super
        STDERR.puts "To view the stanza, run (cd #{stanza_base_dir}; ts server) and open http://localhost:8080/"
      end

      def index_js_fpath
        "#{stanza_dir}/index.js"
      end

      def stanza_html_fpath
        "#{stanza_dir}/templates/stanza.html"
      end

      def sparql_fpath
        "#{stanza_dir}/templates/stanza.rq"
      end
    end
  end
end
