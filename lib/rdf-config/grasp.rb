require 'rdf-config/grasp/comment_generator'
require 'rdf-config/grasp/dataset_type_generator'
require 'rdf-config/grasp/object_type_generator'
require 'rdf-config/grasp/query_type_generator'
require 'rdf-config/grasp/query_generator'

class RDFConfig
  class Grasp
    INDENT = '  '

    def initialize(config)
      @config = config
      @model = Model.new(config)

      @target = File.basename(config.config_dir)
      @query_file_dir = "grasp/#{@target}"
      @schema_file_dir = "grasp/#{@target}/schema"
    end

    def generate
      setup
      generate_dataset_file
      generate_object_type_files
      generate_query_type_file
      generate_query_file

      STDERR.puts 'Grasp files have been created successfully.'
    end

    def generate_dataset_file
      comment_generator = CommentGenerator.new(@config)
      dataset_type_generator = DatasetTypeGenerator.new(@config)
      File.open("#{@schema_file_dir}/dataset.graphql", 'w') do |f|
        f.puts comment_generator.generate
        f.puts dataset_type_generator.generate
      end
    end

    def generate_object_type_files
      @model.subjects.select(&:used_as_object?).each do |subject|
        generate_object_type_file(subject.name)
      end
    end

    def generate_object_type_file(object_type)
      generator = ObjectTypeGenerator.new(@config)
      File.open("#{@schema_file_dir}/#{object_type}.graphql", 'w') do |f|
        f.puts generator.generate(object_type)
      end
    end

    def generate_query_type_file
      generator = QueryTypeGenerator.new(@config)
      File.open("#{@schema_file_dir}/index.graphql", 'w') do |f|
        f.puts generator.generate
      end
    end

    def generate_query_file
      generator = QueryGenerator.new(@config)
      File.open("#{@query_file_dir}/query.graphql", 'w') do |f|
        f.puts generator.generate
      end
    end

    private

    def setup
      unless File.exist?(@schema_file_dir)
        require 'fileutils'
        FileUtils.mkdir_p(@schema_file_dir)
      end
    end
  end
end
