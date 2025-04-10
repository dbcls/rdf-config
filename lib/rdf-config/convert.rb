# frozen_string_literal: true

require 'forwardable'
require_relative 'convert/mix_in/convert_util'
require_relative 'convert/config_parser'
require_relative 'convert/method_parser'
require_relative 'convert/rdf_generator'
require_relative 'convert/validator'
require_relative 'convert/macro'

class RDFConfig
  class Convert
    extend Forwardable
    include MixIn::ConvertUtil

    class InputFileNotFound < StandardError; end
    class InvalidConfig < StandardError; end

    MACRO_DIR_NAME = 'macros'
    MACRO_DIR_PATH = File.join(__dir__, 'convert', MACRO_DIR_NAME)
    SOURCE_FORMATS = %w[csv tsv json xml].freeze
    SOURCE_MACRO_NAME = 'source'
    ROOT_MACRO_NAME = 'root'
    SYSTEM_MACRO_NAMES = [SOURCE_MACRO_NAME, ROOT_MACRO_NAME].freeze
    JSON_LD_SYMBOLS = %w[jsonld json-ld json_ld jsonl].freeze
    JSON_LD_FORMAT_REGEXP = /\A:?jsonld?([\-:]nest)?\z/

    attr_reader :source_subject_map, :subject_config, :object_config, :subject_object_map,
                :convert_method, :macro_names, :format, :output_path

    def_delegators :@config_parser,
                   :subject_converts, :object_converts, :source_subject_map, :source_format_map, :macro_names,
                   :variable_convert, :convert_variable_names, :has_rdf_type_object?

    def initialize(config, opts)
      @config = config
      @format = opts[:format] || ':turtle'
      @output_path = opts[:output_path]
      @generate_context = %w[:context context].include?(@format)

      @config_parser = ConfigParser.new(config, convert_source: opts[:convert_source])
      @config_parser.parse
      @convert_method = {
        subject_converts: @config_parser.subject_converts,
        object_converts: @config_parser.object_converts
      }

      validator = Validator.new(config, **opts.merge(convert: self))
      validator.validate

      @source = begin
        source_subject_map.keys.first
      rescue StandardError
        nil
      end

      @source_file_format = source_format_map[@source].first
    end

    def generate
      if @format =~ JSON_LD_FORMAT_REGEXP || @generate_context
        if @format =~ /\A:?jsonl([\-:]nest)?\z/
          json_ld_generator.generate(per_line: true)
        elsif @generate_context
          json_ld_generator.generate_context
        else
          json_ld_generator.generate
        end
      else
        rdf_generator.generate
      end
    end

    def file_reader(source: @source, file_format: @source_file_format)
      file_format = ext_by_file_path(source) if file_format.to_s.empty?

      case file_format
      when 'csv', 'tsv'
        require_relative 'convert/file_reader/csv_reader'
        CSVReader.new(source, file_format)
      when 'json'
        require_relative 'convert/file_reader/json_reader'
        JSONReader.new(@source)
      when 'xml'
        require_relative 'convert/file_reader/xml_reader'
        XMLReader.new(@source)
      end
    end

    def rdf_converter
      macro = Macro.get_instance(*macro_names)
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/converter/csv_converter'
        CSVConverter.new(@convert_method, macro)
      when 'json'
        require_relative 'convert/converter/json_converter'
        JSONConverter.new(@convert_method, macro)
      when 'xml'
        require_relative 'convert/converter/xml_converter'
        XMLConverter.new(@convert_method, macro)
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

    def json_ld_generator
      case @source_file_format
      when 'csv', 'tsv'
        if @format =~/\A:?jsonl([\-:]nest)?\z/ || @generate_context
          require_relative 'convert/json_ld_generator/csv2json_lines'
          CSV2JSON_Lines.new(@config, self)
        else
          require_relative 'convert/json_ld_generator/csv2json_ld'
          CSV2JSON_LD.new(@config, self)
        end
      end
    end

    def subject_convert_by_name(subject_name)
      subject_converts.select { |convert| convert.keys.first == subject_name }.first
    end

    def bnode_name?(variable_name)
      /\A_BNODE\d+_\z/ =~ variable_name
    end

    def subject_names
      @convert_method[:subject_converts].map { |hash| hash.keys.first }
    end

    def object_names
      # ToDo: Subjectが複数ある場合に正常に動作するか確認する
      @convert_method[:object_converts].values.map { |converts| converts.map { |convert| convert.keys.first} }.flatten.uniq
    end

    def variable_names
      subject_names + object_names
    end
  end
end
