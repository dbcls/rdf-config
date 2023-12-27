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

      @add_namespace = @opts[:add_namespace]
      @query_type_generator = QueryTypeGenerator.new(opts)

      @subject_name_configs = {}

      @config_is_error = false
    end

    def generate
      process_all_configs
      generate_query_type_file
      output_end_message
    end

    def process_all_configs
      configs.each do |config|
        @config_is_error = false
        warn "-- Generate Grasp files by config: #{config.config_dir} --"
        process_config(config)
        warn ''
      end
    end

    def process_config(config)
      setup_by_config(config)
      generate_by_config
    rescue Config::SyntaxError, Config::InvalidConfig, Config::ConfigNotFound, OutputDirExist => e
      @config_is_error = true
      warn e.message
    end

    def generate_by_config
      @model.subjects.each do |subject|
        @subject = subject
        add_subject_name_configs

        if !@add_namespace && @subject_name_configs[subject.name].size > 1
          warn "  * Subject: #{subject.name} ... Skipped because this subject name has already appeared."
          next
        end

        warn "  * Subject: #{subject.name}"
        process_subject
      end
    end

    def generate_dataset_file
      comment_generator = CommentGenerator.new(@config, @opts.merge(subject: @subject))
      dataset_type_generator = DatasetTypeGenerator.new(@config, @opts.merge(subject: @subject))
      union_generator = UnionGenerator.new(@config, @opts.merge(subject: @subject))
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
      "#{subject_type_name(@config, @subject, add_namespace: @add_namespace)}.graphql"
    end

    def setup_by_config(config)
      @config = config

      # Check if the endpoint.yaml file exists.
      # If the endpoint.yaml file does not exist, @config.endpoint throws an exception
      @config.endpoint

      @model = Model.instance(@config)
    end

    def add_subject_name_configs
      @subject_name_configs[@subject.name] = [] unless @subject_name_configs.key?(@subject.name)
      @subject_name_configs[@subject.name] << @config.name
    end

    def configs
      if @config.is_a?(Array)
        @config
      else
        [@config]
      end
    end

    def output_end_message
      unless @add_namespace
        multiple_subject_name = @subject_name_configs.select { |subject_name, config_names| config_names.size > 1 }
        unless multiple_subject_name.empty?
          warn "WARNING: The following subject names are used in several configs."
          multiple_subject_name.keys.sort.each do |subject_name|
            warn "  #{subject_name}: #{multiple_subject_name[subject_name].join(', ')}"
          end
          return
        end
      end

      warn "Grasp files have been generated successfully." unless @config_is_error
    end
  end
end
