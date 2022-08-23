require 'open3'

require_relative '../stanza'

class RDFConfig
  class Stanza
    class Ruby < RDFConfig::Stanza
      def initialize(model, opts = {})
        @stanza_type = 'ruby'

        super
      end

      def generate_template
        setup_stanza_provider if require_stanza_init?

        Dir.chdir(stanza_base_dir) do
          stdout, stderr, status = Open3.capture3("togostanza stanza new #{@name}")
          unless status.success?
            raise StanzaExecutionFailure, "ERROR: Stanza files creation failed.\n#{stderr}"
          end
        end
      rescue Errno::ENOENT => e
        raise StanzaExecutionFailure, "#{e.message}\nMake sure togostanza command is installed or togostanza command path is set in your PATH environment variable."
      end

      def setup_stanza_provider
        STDERR.write "Setup togostanza provider. It will take a while ... "
        STDERR.flush
        stdout, stderr, status = Open3.capture3("togostanza init #{stanza_base_dir}")
        unless status.success?
          STDERR.puts
          raise StanzaExecutionFailure, "ERROR: Stanza init execution failed.\n#{stderr}"
        end

        STDERR.puts "done ."
      end

      def generate_versionspecific_files
        update_stanza_rb
      end

      def update_stanza_rb
        output_to_file(stanza_rb_fpath, stanza_ruby)
      end

      def metadata_hash
        metadata = JSON.parse(File.read(metadata_json_fpath))

        metadata.merge(super)
      end

      def stanza_html
        stanza_html_lines.join("\n")
      end

      def stanza_html_lines
        html_lines = []

        indent_chars = ''
        File.readlines(stanza_html_fpath).each do |line|
          if /(\s*)<body>/ =~ line
            indent_chars = $1
            html_lines << line.chomp
            break
          end
          html_lines << line.chomp
        end

        html_lines << sparql_result_html('', indent_chars)
        html_lines << "#{indent_chars}</body>"
        html_lines << '</html>'

        html_lines
      end

      def stanza_ruby
        <<-EOS
#{ruby_class_def_line}
  property :#{@name} do |#{sparql.parameters.keys.join(', ')}|
    query('#{sparql.endpoint}', '#{sparql_fname}')
  end
end
        EOS
      end

      def ruby_class_def_line
        class_def_line = ''
        File.readlines(stanza_rb_fpath).each do |line|
          if /class\s+\w+\s*\<\s*TogoStanza\:\:Stanza\:\:Base/ =~ line
            class_def_line = line.chomp
            break
          end
        end

        class_def_line
      end

      def after_generate
        super
        STDERR.puts "To view the stanza, run (cd #{stanza_base_dir}; bundle exec rackup) and open http://localhost:9292/"
      end

      def require_stanza_init?
        !File.exist?("#{stanza_base_dir}/Gemfile.lock")
      end

      def stanza_rb_fpath
        "#{stanza_dir}/stanza.rb"
      end

      def stanza_html_fpath
        "#{stanza_dir}/template.hbs"
      end

      def sparql_fname
        "#{@name}.hbs"
      end

      def sparql_fpath
        "#{stanza_dir}/sparql/#{sparql_fname}"
      end

      def stanza_dir
        if /_stanza\z/ =~ @name
          super
        else
          "#{super}_stanza"
        end
      end
    end
  end
end
