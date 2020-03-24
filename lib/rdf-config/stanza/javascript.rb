class RDFConfig
  class Stanza
    class JavaScript < RDFConfig::Stanza
      def initialize(model)
        @stanza_type = 'javascript'

        super
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
        metadata_parameters.each do |key, parameter|
          stanza_usages << { key => parameter['example'] }
        end
        stanza_usage_attr = stanza_usages.map do |usage|
          key = usage.keys.first
          %(#{key}="#{usage[key]}")
        end.join(' ')

        metadata = JSON.parse(File.read(metadata_json_fpath))
        metadata['stanza:label'] = self.metadata['label']
        metadata['stanza:definition'] = self.metadata['definition']
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

      def object_value(value)
        %("{{#{value}}}")
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
