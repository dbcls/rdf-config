require 'uri'
require 'net/http'
require 'json'
require_relative '../config'
require_relative 'common_methods'
require_relative 'query_generator'

class RDFConfig
  class Grasp
    class Client
      include CommonMethods

      GRASP_SERVER = 'http://localhost:4000'.freeze

      def initialize(config, **opts)
        @config = config

        @grasp_server = if opts.key?(:grasp_server)
                          opts[:grasp_server]
                        else
                          GRASP_SERVER
                        end

        @output_dir = opts[:output_dir]

        @http_timeout = 60
        # @http_timeout = 60 * 60 # 1hour
        # @http_timeout = nil

        @response = nil
        @graphql_query = ''
        @graphql_result = ''
      end

      def run
        output_file_path = File.join(@output_dir, "#{@config.name}.txt") if @output_dir
        generate_query(output_file_path)
        run_query(output_file_path)
      rescue StandardError => e
        puts e
      end

      private

      def generate_query(output_file_path)
        @graphql_query = QueryGenerator.new(@config).generate.join("\n")
        output = [
          "-- GraphQL query (SPARQL endpoint: #{endpoint_url}) --", @graphql_query
        ]
        puts output

        return unless output_file_path

        File.open(output_file_path, 'w') do |f|
          f.puts output.join("\n")
          f.puts
        end
      end

      def run_query(output_file_path)
        start_time = Time.now
        send_query
        @graphql_result = case @response
                          when Net::HTTPSuccess
                            JSON.pretty_generate(JSON.parse(@response.body))
                          else
                            @response.body
                          end
      rescue StandardError => e
        @graphql_result = e.message
      ensure
        end_time = Time.now
        output_result(output_file_path, end_time - start_time)
      end

      def send_query
        url = URI.parse(@grasp_server)
        http = Net::HTTP.new(url.host, url.port)
        http.read_timeout = @http_timeout
        path = if url.path.to_s.empty?
                 '/'
               else
                 url.path
               end
        @response = http.post(path, post_data.to_json, http_header)
      end

      def http_header
        {
          'Content-Type' => 'application/json'
        }
      end

      def post_data
        {
          operationName: nil,
          variables: {},
          query: @graphql_query
        }
      end

      def output_result(output_file_path, run_time_sec)
        output = [
          '-- GraphQL result --'
        ]
        output << "HTTP status: #{@response.code} #{@response.message}" unless @response.nil?
        output << @graphql_result
        output << ''
        # output << "Run time: #{run_time_sec} sec (#{run_time_sec.to_i / 60} min #{run_time_sec % 60} sec)"
        output << "Run time: #{run_time_sec.round(2)} sec"
        puts output

        return unless output_file_path

        File.open(output_file_path, 'a') do |f|
          f.puts output.join("\n")
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  params = ARGV.getopts('o:')
  output_dir = params['o']
  if output_dir && !File.exist?(output_dir)
    require 'fileutils'
    FileUtils.mkdir_p(output_dir)
  end

  opts = {}
  opts.merge!(output_dir:) if output_dir
  opts.merge!(grasp_server: ENV['GRASP_SERVER']) if ENV['GRASP_SERVER']
  ARGV.each do |config_dir|
    puts "--- Config directory: #{config_dir} ---"
    client = RDFConfig::Grasp::Client.new(RDFConfig::Config.new(config_dir), **opts)
    client.run
  end
end
