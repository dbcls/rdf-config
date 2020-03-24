class RDFConfig
  class Stanza
    class Ruby < RDFConfig::Stanza
      def initialize(model)
        @stanza_type = 'ruby'

        super
        @base_dir = "#{output_dir}/#{@name}"
        @generate_template_cmd = "togostanza init #{output_dir}; cd #{output_dir}; togostanza stanza new #{@name}"
      end

      def generate
        generate_template
        update_metadata_json
        update_stanza_html
        update_stanza_rb
        generate_sparql_hbs
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

          f.puts "  property :#{@name} do |#{stanza_parameters.keys.join(', ')}|"
          f.puts "    query('#{@sparql.endpoint}', '#{sparql_hbs_fname}')"
          f.puts '  end'
          f.puts 'end'
        end
      end

      def generate_sparql_hbs
        File.open(sparql_hbs_fpath, 'w') do |f|
          f.puts sparql_query
        end
      end

      def stanza_html_fpath
        "#{@base_dir}/template.hbs"
      end

      def stanza_rb_fpath
        "#{@base_dir}/stanza.rb"
      end

      def sparql_hbs_fname
        "#{@name}.hbs"
      end

      def sparql_hbs_fpath
        File.expand_path("#{@base_dir}/sparql/#{sparql_hbs_fname}")
      end
    end
  end
end
