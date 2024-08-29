# frozen_string_literal: true

require 'yaml'
require_relative 'mix_in/convert_util'

class RDFConfig
  class Convert
    class ConfigParser
      class ParseError < StandardError; end

      include MixIn::ConvertUtil

      attr_reader :subject_converts, :object_converts, :variable_converts, :source_subject_map, :source_format_map,
                  :macro_names, :variable_convert, :convert_variable_names

      CONFIG_FILES_KEY = 'config_files'
      SUBJECT_KEY = 'subject'
      OBJECTS_KEY = 'objects'

      def initialize(config, **opts)
        @config = config

        @validator = Validator.new(config)

        @model = Model.instance(config)
        @method_parser = MethodParser.new

        @subject_converts = []
        @object_converts = {}
        @source_subject_map = {}

        @variable_convert = {}
        @convert_variable_names = []

        @source_format_map = {}
        @target_source_file_path = nil

        @subject_config = {}
        @object_config = {}

        @subject_name_stack = []
        @subject_object_map = {}
        @bnode_no = 0

        @macro_names = []

        @convert_source = opts[:convert_source]
        @convert_source_file = (@convert_source if !@convert_source.nil? && File.file?(@convert_source))
      end

      def parse
        validate_config(@config.convert)
        raise InvalidConfig, @validator.format_error_message if @validator.error?

        @config.convert.each do |convert_config|
          key = convert_config.keys.first
          if key == CONFIG_FILES_KEY
            # convert_config is array of convert config file path
            config_files = if convert_config[key].is_a?(Array)
                             convert_config[key].map { |path| @config.absolute_path(path) }
                           else
                             [@config.absolute_path(convert_config.to_s)]
                           end
            load_config_files(config_files)
            raise InvalidConfig, @validator.format_error_message if @validator.error?
          else
            # key is subject name
            parse_subject_config(key, convert_config[key])
          end
        end
      end

      def has_rdf_type_object?
        object_names.select do |object_name|
          triple = @model.find_by_object_name(object_name)
          triple.predicates.select(&:rdf_type?).count > 0
        end.count > 0
      end

      def object_names
        @object_config.keys
      end

      private

      def load_config_files(config_files)
        config_files = [config_files.to_s] unless config_files.is_a?(Array)

        config_files.each do |config_file|
          if File.exist?(config_file)
            load_config_file(config_file)
          else
            @validator.add_error(%(Config file "#{config_file}" does not found.))
          end
        end
      end

      def load_config_file(config_file_path)
        convert_config = YAML.load_file(config_file_path)
        if validate_config(convert_config, convert_config_file_path: config_file_path)
          load_config(convert_config)
        end
      end

      def load_config(convert_configs)
        convert_configs.each do |subject_config|
          subject_name = subject_config.keys.first
          parse_subject_config(subject_name, subject_config[subject_name])
        end
      end

      def parse_subject_config(subject_name, subject_configs, child: false)
        @subject_name_stack.push(subject_name)
        @subject_object_map[subject_name] = []
        @subject_config[subject_name] = []

        to_array(subject_configs).each do |convert_step|
          parse_subject_convert_step(subject_name, convert_step)
        end

        unless @source_subject_map.values.flatten.include?(subject_name)
          add_source_subject_map(@convert_source_file, subject_name) unless @source_subject_map.value?(subject_name)
        end

        @subject_name_stack.pop
      end

      def parse_subject_convert_step(subject_name, convert_step)
        case convert_step
        when Hash
          parse_hash_convert_step(subject_name, convert_step)
        when String
          unless convert_step.start_with?(SOURCE_MACRO_NAME)
            raise ParseError, "ERROR: Unexpected convert setting: #{subject_name}, #{convert_step}"
          end

          parse_converter(subject_name, convert_step)
        else
          raise ParseError, "ERROR: Unexpected convert setting: #{subject_name}, #{convert_step}"
        end
      end

      def parse_hash_convert_step(subject_name, convert_step)
        if convert_step.key?(SUBJECT_KEY)
          subject_converts = parse_subject_converts(subject_name, convert_step[SUBJECT_KEY])
          add_subject_convert(subject_name, subject_converts)
        elsif convert_step.key?(OBJECTS_KEY)
          parse_objects_config(subject_name, convert_step[OBJECTS_KEY])
        elsif convert_variable?(convert_step.keys.first)
          parse_variable_config(convert_step)
        else
          raise ParseError, "ERROR: Unexpected convert setting: #{subject_name}, #{convert_step}"
        end
      end

      def parse_subject_converts(subject_name, subject_convert_steps)
        subject_converts = []
        subject_convert_steps.each do |subject_convert|
          subject_converts << parse_converter(subject_name, subject_convert)
          @subject_config[subject_name] << subject_convert
        end

        subject_converts
      end

      def parse_bnode_config(bnode_config)
        subject_name = bnode_name
        @subject_object_map[@subject_name_stack.last] << subject_name
        parse_subject_config(subject_name, bnode_config)
      end

      def parse_objects_config(subject_name, objects_config)
        objects_config.each do |object_config|
          object_name = object_config.keys.first
          if @model.subject?(object_name)
            parse_subject_config(object_name, object_config[object_name], child: true)
            @subject_object_map[subject_name] << object_name
          elsif object_name.to_s == '[]'
            parse_bnode_config(object_config[object_name])
          else
            add_object_convert(subject_name, object_name, parse_object_config(object_name, object_config))
          end
        end
      end

      def parse_object_config(object_name, object_config)
        converts = []
        @subject_object_map[@subject_name_stack.last] << object_name

        @object_config[object_name] = if object_config[object_name].is_a?(Array)
                                        object_config[object_name]
                                      else
                                        [object_config[object_name]]
                                      end

        @object_config[object_name].each do |obj_conf|
          converts << parse_converter(object_name, obj_conf)
        end

        @object_config[object_name].unshift({ _subject_name: @subject_name_stack.last })

        converts
      end

      def parse_variable_config(variable_convert)
        variable_name = variable_convert.keys.first
        convert_def = parse_converter(variable_name, variable_convert[variable_name])
        add_variable_convert(variable_name, convert_def)
        add_convert_variable_name(variable_name)
      end

      def parse_converter(variable_name, converter)
        if converter.is_a?(Hash)
          convert_variable_name = converter.keys.first
          converter = converter[convert_variable_name]
        elsif convert_variable?(variable_name)
          convert_variable_name = variable_name
        else
          convert_variable_name = nil
        end

        is_macro = true
        begin
          method = @method_parser.parse(converter)
        rescue Parslet::ParseFailed => e
          # Here comes tha case where the converter is not a method definition
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
          process_source_macro(method_def[:args_][:arg_][1..-2], variable_name)
        elsif Convert::SOURCE_FORMATS.include?(macro_name)
          add_source_format_map(@target_source_file_path, macro_name)
        end

        if @source_file_format.nil? && !method.nil? && SOURCE_FORMATS.include?(method[:method_name_])
          @source_file_format = method[:method_name_]
        end

        method_def
      end

      def process_source_macro(source_by_config, variable_name)
        @target_source_file_path = source_file_path(source_by_config)
        add_source_subject_map(@target_source_file_path, variable_name)
        @source_format_map[@target_source_file_path] = [] unless @source_format_map.key?(@target_source_file_path)
      end

      def add_source_subject_map(source, subject_name)
        @source_subject_map[source] = [] unless @source_subject_map.key?(source)

        @source_subject_map[source] << subject_name
      end

      def add_source_format_map(source, macro_name)
        source = @convert_source_file unless @convert_source_file.nil?
        @source_format_map[source] = [] unless @source_format_map.key?(source)

        @source_format_map[source] << macro_name unless @source_format_map[source].include?(macro_name)
      end

      def source_file_path(source_by_config)
        return @convert_source_file if @convert_source_file

        if absolute_path?(source_by_config)
          source_by_config
        elsif source_by_config.start_with?('~')
          File.expand_path(source_by_config)
        else
          File.expand_path(source_by_config, @convert_source)
        end
      end

      def add_variable_convert(variable_name, convert)
        @variable_convert[variable_name] = [] unless @variable_convert.key?(variable_name)
        @variable_convert[variable_name] << convert
      end

      def add_subject_convert(subject_name, convert)
        @subject_converts << { subject_name => convert }
      end

      def add_object_convert(subject_name, object_name, convert)
        @object_converts[subject_name] = [] unless @object_converts.key?(subject_name)
        @object_converts[subject_name] << { object_name => convert }
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

      def absolute_path?(path)
        if File.respond_to?(:absolute_path?)
          File.absolute_path?(path)
        elsif File::ALT_SEPARATOR
          path =~ /\A[a-zA-Z]:\\/ || path.start_with?('\\')
        else
          path.start_with?('/')
        end
      end

      def validate_config(convert_config, convert_config_file_path: 'convert.yaml')
        unless convert_config.is_a?(Array)
          @validator.add_error("#{convert_config_file_path} must be an array of conversion settings for each subject.")
          return false
        end

        validate_subjects(convert_config)
      end

      def validate_subjects(convert_config)
        subject_names = convert_config.map { |subject_convert| subject_convert.keys.first }
        duplicate_subject_names = subject_names.select { |subject_name|  subject_names.count(subject_name) > 1 }.uniq
        if duplicate_subject_names.empty?
          true
        else
          @validator.add_error("Duplicate subject name in convert.yaml: #{duplicate_subject_names.join(', ')}")
          false
        end
      end
    end
  end
end
