# frozen_string_literal: true

require_relative 'convert/method_parser'
require_relative 'convert/rdf_generator'
require_relative 'convert/validator'

class RDFConfig
  class Convert
    class InputFileNotFound < StandardError; end
    class InvalidConfig < StandardError; end

    MACRO_DIR_NAME = 'macros'
    SOURCE_FORMATS = %w[csv tsv json xml].freeze
    ROOT_MACRO_NAME = 'root'
    VARIABLES_KEY = 'variables'

    attr_reader :root_subjects, :subject_config, :object_config, :subject_object_map, :convert_method

    def initialize(config, opts)
      @config = config

      @source = File.expand_path(opts[:input_file])
      raise InputFileNotFound, "Input file (#{@source}) does not exist." unless File.exist?(@source)

      @model = Model.instance(config)

      @root_subjects = config.convert.keys

      @bnode_no = 0
      @subject_config = {}
      @object_config = {}
      @subject_object_map = {}
      @subject_name_stack = []

      parse_config

      validator = Validator.new(config, **opts.merge(convert: self))
      validator.validate

      @convert_method = validator.convert_method
      @source_file_format = validator.source_file_format
    end

    def generate
      rdf_generator.generate
    end

    def file_reader
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/file_reader/csv_reader'
        CSVReader.new(@source, @source_file_format)
      when 'json'
        require_relative 'convert/file_reader/json_reader'
        JSONReader.new(@source)
      when 'xml'
        require_relative 'convert/file_reader/xml_reader'
        XMLReader.new(@source)
      end
    end

    def rdf_converter
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/converter/csv_converter'
        CSVConverter.new(@convert_method)
      when 'json'
        require_relative 'convert/converter/json_converter'
        JSONConverter.new(@convert_method)
      when 'xml'
        require_relative 'convert/converter/xml_converter'
        XMLConverter.new(@convert_method)
      end
    end

    def rdf_generator
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/rdf_generator/csv2rdf'
        CSV2RDF.new(@config, self)
      when 'json'
        require_relative 'convert/rdf_generator/json2rdf'
        JSON2RDF.new(@config, self)
      when 'xml'
        require_relative 'convert/rdf_generator/xml2rdf'
        XML2RDF.new(@config, self)
      end
    end

    def bnode_name?(variable_name)
      /\A_BNODE\d+_\z/ =~ variable_name
    end

    def subject_names
      @subject_config.keys
    end

    def object_names
      @object_config.keys
    end

    private

    def parse_config
      @config.convert.each do |subject_name, subject_configs|
        parse_subject_config(subject_name, subject_configs)
      end
    end

    def parse_subject_config(subject_name, subject_configs, child: false)
      @subject_name_stack.push(subject_name)
      @subject_object_map[subject_name] = []
      @subject_config[subject_name] = []
      subject_configs.each do |config|
        if config.is_a?(Hash) && config.key?(VARIABLES_KEY)
          config[VARIABLES_KEY].each do |object_config|
            object_name = object_config.keys.first
            if @model.subject?(object_name)
              parse_subject_config(object_name, object_config[object_name], child: true)
              @subject_object_map[subject_name] << object_name
            elsif object_name.to_s == '[]'
              parse_bnode_config(object_config[object_name])
            else
              parse_object_config(object_name, object_config)
            end
          end
        else
          @subject_config[subject_name] << config
        end
      end
      @subject_name_stack.pop
    end

    def parse_bnode_config(bnode_config)
      subject_name = bnode_name
      @subject_object_map[@subject_name_stack.last] << subject_name
      parse_subject_config(subject_name, bnode_config)
    end

    def parse_object_config(object_name, object_config)
      @subject_object_map[@subject_name_stack.last] << object_name

      @object_config[object_name] = if object_config[object_name].is_a?(Array)
                                      object_config[object_name]
                                    else
                                      [object_config[object_name]]
                                    end
      @object_config[object_name].unshift({ _subject_name: @subject_name_stack.last })
    end

    def bnode_name
      @bnode_no += 1

      "_BNODE#{@bnode_no}_"
    end
  end
end
