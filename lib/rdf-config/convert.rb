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
    SOURCE_MACRO_NAME = 'source'
    ROOT_MACRO_NAME = 'root'
    VARIABLES_KEY = 'variables'
    CONFIG_FILES_KEY = 'config_files'
    SYSTEM_MACRO_NAMES = [SOURCE_MACRO_NAME, ROOT_MACRO_NAME].freeze

    attr_reader :source_subject_map, :root_subjects, :subject_config, :object_config, :subject_object_map,
                :convert_method, :macro_names, :convert_variable_names

    def initialize(config, opts)
      @config = config

      @model = Model.instance(config)
      @method_parser = MethodParser.new

      @root_subjects = config.convert.keys

      @bnode_no = 0
      @subject_config = {}
      @object_config = {}
      @source_subject_map = {}
      @subject_object_map = {}
      @subject_name_stack = []

      @convert_method = {}
      @macro_names = []
      @convert_variable_names = []

      parse_config

      validator = Validator.new(config, **opts.merge(convert: self))
      validator.validate

      @source = begin
        @source_subject_map.keys.first
      rescue StandardError
        nil
      end

      @source_file_format = if @source.nil?
                              nil
                            else
                              ext_by_file_path(@source)
                            end
    end

    def generate
      rdf_generator.generate
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
      @config.convert.each do |key, convert_config|
        if key == CONFIG_FILES_KEY
          # convert_config is array of convert config file path
          config_files = if convert_config.is_a?(Array)
                           convert_config.map { |path| @config.absolute_path(path) }
                         else
                           [@config.absolute_path(convert_config.to_s)]
                         end
          load_config_files(config_files)
        else
          # key is subject name
          parse_subject_config(key, convert_config)
        end
      end
    end

    def load_config_files(config_files)
      config_files = [config_files.to_s] unless config_files.is_a?(Array)

      errors = []
      config_files.each do |config_file|
        if File.exist?(config_file)
          load_config_file(config_file)
        else
          errors << %(  * Config file "#{config_file}" does not found.)
        end
      end

      raise InvalidConfig, errors.unshift('ERROR:').join("\n") unless errors.empty?
    end

    def load_config_file(config_file_path)
      YAML.load_file(config_file_path).each do |subject_name, convert_config|
        parse_subject_config(subject_name, convert_config)
      end
    end

    def parse_subject_config(subject_name, subject_configs, child: false)
      @subject_name_stack.push(subject_name)
      @subject_object_map[subject_name] = []
      @subject_config[subject_name] = []
      to_array(subject_configs).each do |config|
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
          add_convert_method(subject_name, parse_converter(subject_name, config))
          @subject_config[subject_name] << config
          add_convert_variable_name(config.keys.first) if config.is_a?(Hash)
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

      @object_config[object_name].each do |obj_conf|
        add_convert_method(object_name, parse_converter(object_name, obj_conf))
        add_convert_variable_name(obj_conf.keys.first) if obj_conf.is_a?(Hash)
      end

      @object_config[object_name].unshift({ _subject_name: @subject_name_stack.last })
    end

    def parse_converter(variable_name, converter)
      if converter.is_a?(Hash)
        convert_variable_name = converter.keys.first
        converter = converter[convert_variable_name]
      elsif variable_name[0] == '$'
        convert_variable_name = variable_name
      else
        convert_variable_name = nil
      end

      is_macro = true
      begin
        method = @method_parser.parse(converter)
      rescue Parslet::ParseFailed
        is_macro = false
      end

      method_def = if is_macro
                     {
                       method_name_: method[:method_name_].to_str,
                       args_: method.key?(:args_) ? method[:args_].map { |k, v| [k, v.to_s] }.to_h : nil,
                       variable_name: convert_variable_name
                     }
                   else
                     {
                       method_name_: 'str',
                       args_: { arg_: converter },
                       variable_name: convert_variable_name
                     }
                   end
      macro_name = method_def[:method_name_].to_s
      add_macro_name(macro_name)

      if macro_name == SOURCE_MACRO_NAME
        source = File.expand_path(method_def[:args_][:arg_][1..-2])
        add_source_subject_map(source, variable_name)
      end

      if @source_file_format.nil? && SOURCE_FORMATS.include?(method[:method_name_])
        @source_file_format = method[:method_name_]
      end

      method_def
    end

    def add_source_subject_map(source, subject_name)
      @source_subject_map[source] = [] unless @source_subject_map.key?(source)

      @source_subject_map[source] << subject_name
    end

    def add_convert_method(variable_name, method)
      @convert_method[variable_name] = [] unless @convert_method.key?(variable_name)

      @convert_method[variable_name] << method
    end

    def add_macro_name(macro_name)
      @macro_names << macro_name unless @macro_names.include?(macro_name)
    end

    def add_convert_variable_name(variable_name)
      @convert_variable_names << variable_name unless @convert_variable_names.include?(variable_name)
    end

    # TODO This code was moved from validator.rb > validate method.
    # Investigate how it is used and if it needs to be used.
    def add_child_method_defs
      @config.convert_method.each_key do |variable_name|
        method_defs = []
        @convert_method[variable_name].each do |method_def|
          case method_def[:method_name_]
          when ROOT_MACRO_NAME
            @root_path = method_def[:args_][:arg_][1..-2]
          end

          if method_def[:method_name_] == @source_file_format
            case @source_file_format
            when 'json'
              method_def[:args_][:arg_] =
                [
                  method_def[:args_][:arg_][0],
                  @root_path,
                  method_def[:args_][:arg_][1..-2],
                  method_def[:args_][:arg_][-1]
                ].join
            when 'xml'
            end
          end
          method_defs << method_def
        end
        add_convert_method(variable_name, method_defs)
      end
    end

    def ext_by_file_path(file_path)
      ext = File.extname(file_path)
      ext = ext[1..] if ext.to_s.size.positive?

      ext
    end

    def bnode_name
      @bnode_no += 1

      "_BNODE#{@bnode_no}_"
    end

    def to_array(obj)
      if obj.is_a?(Array)
        obj
      else
        [obj.to_s]
      end
    end
  end
end
