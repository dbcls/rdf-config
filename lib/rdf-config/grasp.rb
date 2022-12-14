require 'fileutils'

require_relative 'grasp/data_type'
require_relative 'grasp/comment_generator'
require_relative 'grasp/dataset_type_generator'
require_relative 'grasp/union_generator'
require_relative 'grasp/object_type_generator'
require_relative 'grasp/query_type_generator'
require_relative 'grasp/query_generator'

class RDFConfig
  class Grasp
    class GraspError < StandardError; end
    class GraspConfigNotFound < StandardError; end
    class OutputDirExist < StandardError; end

    include CommonMethods
    include DataType

    DEFAULT_OUTPUT_DIR = 'grasp'.freeze
    QUERY_TYPE_FILE_NAME = 'index.graphql'.freeze
    GRASP_RESOURCES_DIR = File.expand_path(File.join(__dir__, '..', '..', 'grasp'))
    INDENT = '  '.freeze

    def initialize(config, opts)
      @config = config
      @opts = opts
      @output_dir = if opts[:output_dir].to_s.length.positive?
                      File.expand_path(opts[:output_dir])
                    else
                      DEFAULT_OUTPUT_DIR
                    end
      raise OutputDirExist, "Output directory '#{@output_dir}' already exists." if File.exist?(@output_dir)

      FileUtils.mkdir_p(@output_dir)

      @query_type_generator = QueryTypeGenerator.new
    end

    def generate
      process_all_configs
      generate_query_type_file

      warn 'Grasp files have been generated successfully.'
    end

    def process_all_configs
      configs.each do |config|
        warn "-- Generate Grasp files by config: #{config.config_dir} --"
        process_config(config)
      end
    end

    def process_config(config)
      setup_by_config(config)
      generate_by_config
    rescue Config::InvalidConfig, Config::ConfigNotFound, OutputDirExist => e
      warn e.message
    end

    def generate_by_config
      @model.subjects.each do |subject|
        if subject.name.to_s == '[]'
          # warn '      Skip this subject'
          next
        end
        warn "  * Subject: #{subject.name}"

        @subject = subject
        process_subject
      end
    end

    def generate_dataset_file
      comment_generator = CommentGenerator.new(@config, @opts.merge(subject: @subject))
      dataset_type_generator = DatasetTypeGenerator.new(@config, subject: @subject)
      union_generator = UnionGenerator.new(@config, subject: @subject)
      File.open(File.join(@output_dir, dataset_filename), 'w') do |f|
        f.puts comment_generator.generate
        f.puts dataset_type_generator.generate
        f.puts union_generator.generate
      end
    end

    def generate_query_type_file
      File.open(File.join(@output_dir, QUERY_TYPE_FILE_NAME), 'w') do |f|
        f.puts @query_type_generator.generate.join("\n")
      end
    end

    private

    def process_subject
      generate_dataset_file
      @query_type_generator.add(@config, @subject)
    end

    def dataset_filename
      "#{subject_type_name(@config, @subject)}.graphql"
    end

    def setup_by_config(config)
      @config = config

      # Check if the endpoint.yaml file exists.
      # If the endpoint.yaml file does not exist, @config.endpoint throws an exception
      @config.endpoint

      @model = Model.instance(@config)
    end

    def configs
      if @config.is_a?(Array)
        @config
      else
        [@config]
      end
    end
  end
end
