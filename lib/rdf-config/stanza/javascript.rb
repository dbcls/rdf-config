require 'rbconfig'
require 'English'
require 'open3'
require 'io/console'

module SafePty
  def self.spawn(command, &block)
    PTY.spawn(command) do |read, write, pid|
      begin
        yield read, write, pid
      rescue Errno::EIO
      ensure
        Process.wait pid
      end
    end

    $CHILD_STATUS.exitstatus
  end
end

class RDFConfig
  class Stanza
    class JavaScript < Stanza
      def initialize(config, opts = {})
        if %w[mswin msys mingw mingw32 cygwin bccwin wince emc].include?(RbConfig::CONFIG['host_os'])
          raise StanzaExecutionFailure, 'If the OS is Windows, Stanza cannot be generated.'
        end

        require 'pty'
        require 'expect'

        @stanza_type = 'javascript'

        super

        return if @stanza_name.empty?

        if File.exist?(stanza_base_dir) && !File.exist?("#{stanza_base_dir}/package-lock.json")
          raise StanzaExecutionFailure,
                "Stanza repository directory: #{stanza_base_dir} exists, but it seems that stanza repository initialization fails, " +
                "so please delete the #{stanza_base_dir} directory."
        end

        return unless File.exist?(stanza_dir)

        raise StanzaExecutionFailure, "Stanza directory: #{stanza_dir} already exists."
      end

      def init_stanza
        return if File.exist?("#{stanza_base_dir}/package-lock.json")

        dirname = File.dirname(stanza_base_dir)
        mkdir(dirname) unless File.exist?(dirname)

        basename = File.basename(stanza_base_dir)

        $stderr.puts "Initialize a togostanza repository."
        cmd = "npx togostanza init --name #{basename} --package-manager npm"
        $stderr.puts "Execute command: #{cmd}"

        $expect_verbose = true
        git_repository = ''
        Dir.chdir(dirname) do
          exit_status = SafePty.spawn(cmd) do |read, write, pid|
            write.sync = true

            read.expect(/Git repository URL \(leave blank if you don't need to push to a remote Git repo/) do |line|
              $expect_verbose = false
            end

            read.expect(/sitory\):.*\z/) do |line|
              print "sitory): "
              git_repository = STDIN.gets.strip
              write.puts git_repository
            end

            read.expect(/license:.*\(.*\).+\z/) do |line|
              print "\e[32m?\e[0m \e[1mlicense\e[m \e[2m(MIT)\e[0m: "
              license = STDIN.gets
              license = 'MIT' if license.empty?
              write.puts license
            end
            read.readline
            $expect_verbose = true

            unless git_repository.empty?
              read.expect(/Username for (.+): /) do |line|
                write.puts STDIN.gets
              end

              read.expect(/Password for (.+): /) do |line|
                password = STDIN.noecho(&:gets)
                write.puts password
              end
            end

            read.expect(/create mode 100644 package.json/) do |line|
              # puts line
            end

            until read.eof? do
              read.readline
            end
          end
        end

        puts
        puts
      rescue Errno::ENOENT => e
        raise StanzaExecutionFailure, "#{e.message}\nMake sure Node.js is installed or npx command path is set in your PATH environment variable."
      end

      def generate_template
        $expect_verbose = false
        cmd = %Q(npx togostanza generate stanza #{@name} --label "#{label}" --definition "#{definition}")
        $stderr.puts "Execute command: #{cmd}"
        Dir.chdir(stanza_base_dir) do
          exit_status = SafePty.spawn(cmd) do |read, write, pid|
            write.sync = true

            read.expect(/license:.*\(.*\).+\z/) do |line|
              print "\e[32m?\e[0m \e[1mlicense\e[m \e[2m(MIT)\e[0m: "
              write.puts STDIN.gets
            end

            read.expect(/author:.*\((.*)\).+\z/) do |line|
              print "\e[32m?\e[0m \e[1mauthor\e[0m \e[2m(#{line[1]})\e[0m: "
              write.puts STDIN.gets
            end
            line = read.readline

            line = read.readline
            if /conflict/ =~ line
              puts line
              $expect_verbose = true
              read.expect(/Overwrite.+\z/) do |line|
                write.puts STDIN.gets
              end
              $expect_verbose = false
            end

            until read.eof? do
              puts read.readline
            end
          end
        end
        puts
      rescue Errno::ENOENT => e
        raise StanzaExecutionFailure, "#{e.message}\nMake sure Node.js is installed or npx command path is set in your PATH environment variable."
      end

      def generate_versionspecific_files
        update_index_js
      end

      def update_index_js
        output_to_file(index_js_fpath, index_js)
      end

      def metadata_hash
        stanza_usage_attr = parameters.map { |name, value| %(#{name}="#{value}") }.join(' ')
        metadata = JSON.parse(File.read(metadata_json_fpath))
        metadata['stanza:usage'] = "<togostanza-#{@name} #{stanza_usage_attr}></togostanza-#{@name}>"

        metadata.merge(super('stanza:'))
      end

      def stanza_html
        sparql_result_html('.value')
      end

      def index_js
        parameter_lines = []
        parameters.each do |name, value|
          parameter_lines << %Q(#{' ' * 10}#{name}: this.params['#{name}'],)
        end

        <<-EOS
import Stanza from 'togostanza/stanza';

export default class #{@name.split('_').map(&:capitalize).join} extends Stanza {
  async render() {
    try {
      const results = await this.query({
        endpoint: '#{sparql.endpoint}',
        template: 'stanza.rq.hbs',
        parameters: {
#{parameter_lines.join("\n")}
        }
      });

      this.renderTemplate(
        {
          template: 'stanza.html.hbs',
          parameters: {
            #{@name}: results.results.bindings
          }
        }
      );
    } catch (e) {
      console.error(e);
    }
  }
}
EOS
      end

      def before_generate
        init_stanza
      end

      def after_generate
        super
        STDERR.puts "To view the stanza, run (cd #{stanza_base_dir}; npx togostanza serve) and open http://localhost:8080/"
      end

      def stanza_base_dir
        output_dir
      end

      def index_js_fpath
        "#{stanza_dir}/index.js"
      end

      def stanza_html_fpath
        "#{stanza_dir}/templates/stanza.html.hbs"
      end

      def sparql_fpath
        "#{stanza_dir}/templates/stanza.rq.hbs"
      end

      def stanza_dir
        "#{stanza_base_dir}/stanzas/#{to_kebab_case(@name)}"
      end

      def parameters_for_metadata(prefix = '')
        params = []

        parameters.each do |name, value|
          triple = model.find_by_object_name(name)
          next if triple.nil?

          params << {
            "#{prefix}key" => name,
            "#{prefix}example" => value,
            "#{prefix}description" => "#{triple.subject.name} / #{triple.property_path(' / ')} (FIXME: in metadata.json)",
            "#{prefix}required" => triple.predicates.last.required?
          }
        end

        params
      end

      def parameters
        sparql_parameters = sparql_conf['parameters'] || {}
        sparql_queries.each do |query|
          variable_name, value = query.to_s.split('=', 2)
          next if value.nil?

          sparql_parameters[variable_name] = value
        end

        sparql_parameters
      end

      def model
        @model ||= RDFConfig::Model.new(@config)
      end

      def to_kebab_case(str)
        return '' if str.strip.empty?

        parts = str.to_s.split(/[^A-Za-z0-9]/).reject(&:empty?).map do |s|
          s.gsub(/([^A-Z])([A-Z])/) { "#{$1}-#{$2.downcase}" }
        end

        ([parts.shift.downcase] + parts.map{|s| "-#{s.downcase}"}).join
      end

      def escape_js_string(string)
        string.to_s.gsub('"', %Q(\\"))
      end

      def sparql_queries
        if @opts.key?(:query)
          @opts[:query].is_a?(Array) ? @opts[:query] : [@opts[:query].to_s]
        else
          []
        end
      end
    end
  end
end
