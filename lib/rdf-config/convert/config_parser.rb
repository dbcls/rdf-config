# frozen_string_literal: true

require 'yaml'
require 'forwardable'
require_relative 'validator'
require_relative 'mix_in/convert_util'
require_relative 'parser/method_parser'

class RDFConfig
  class Convert
    class ConfigParser
      class ParseError < StandardError; end

      extend Forwardable
      include MixIn::ConvertUtil

      attr_reader :subject_converts, :object_converts, :source_subject_map, :source_format_map,
                  :macro_names, :variable_convert, :convert_variable_names

      def_delegators :@yaml_parser, :object_names

      CONFIG_FILES_KEY = 'config_files'
      SUBJECT_KEY = 'subject'
      OBJECTS_KEY = 'objects'

      def initialize(config, **opts)
        @config = config
        @yaml_parser = opts[:yaml_parser]

        @validator = Validator.new(config)

        @model = Model.instance(config)
        @method_parser = MethodParser.new

        @subject_converts = {}
        @object_converts = {}
        @source_subject_map = {}
        @macro_names = []

        @variable_convert = {}
        @convert_variable_names = []

        @source_format_map = {}
        @target_source_file_path = nil

        @subject_config = {}
        @object_config = {}

        @subject_name_stack = []
        @subject_object_map = {}
        @bnode_no = 0

        @convert_source = opts[:convert_source]
        @convert_source_file = (@convert_source if !@convert_source.nil? && File.file?(@convert_source))
      end

      def parse
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
            @subject_converts[key] = []
            parse_subject_converts(key)
            parse_object_converts(key)
          end
        end
      end

      def parse_converter(variable_name, converter)
        if converter.is_a?(Hash)
          name = converter.keys.first.value
          if convert_variable?(name)
            convert_variable_name = name
            converter = converter.values.first
          else
            if name.start_with?('switch')
              require_relative 'processor/switch_processor'
              switch_processor = Processor::SwitchProcessor.new(variable_name, name, converter.values.first)
              switch_processor.parse_convert_process(self)
              return switch_processor
            end
          end
        elsif convert_variable?(variable_name)
          convert_variable_name = variable_name
        else
          convert_variable_name = nil
        end

        is_macro = !converter.quoted?
        begin
          method = @method_parser.parse(converter.value)
        rescue Parslet::ParseFailed => e
          # Here comes the case where the converter is not a method definition
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
          process_source_macro(method_def, variable_name)
        elsif Convert::SOURCE_FORMATS.include?(macro_name)
          add_source_format_map(@target_source_file_path, macro_name)
        end

        if @source_file_format.nil? && !method.nil? && SOURCE_FORMATS.include?(method[:method_name_])
          @source_file_format = method[:method_name_]
        end

        method_def
      end

      def has_rdf_type_object?
        object_names.reject { |object_name| convert_variable?(object_name) }.select do |object_name|
          triple = @model.find_by_object_name(object_name)
          triple&.predicates&.select(&:rdf_type?)&.count&.positive?
        end.count.positive?
      end

      private

      def parse_subject_converts(subject_name)
        @yaml_parser.subject_converts(subject_name).map do |subject_convert|
          add_subject_convert(subject_name, parse_converter(subject_name, subject_convert))
        end
      end

      def parse_object_converts(subject_name)
        @yaml_parser.object_convert[subject_name].each do |object_name, object_converts|
          object_converts.each do |object_convert|
            add_object_convert(subject_name, object_name, parse_converter(object_name, object_convert))
          end
        end
      end

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
        # TODO ファイルが分割されている場合、分割されたファイルを読み込んだ際にValidationを行う
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
          add_subject_convert(subject_name, convert_step)
        when String
          unless convert_step.start_with?(SOURCE_MACRO_NAME)
            raise ParseError, "ERROR: Unexpected convert setting: #{subject_name}, #{convert_step}"
          end

          parse_converter(subject_name, convert_step)
        else
          raise ParseError, "ERROR: Unexpected convert setting: #{subject_name}, #{convert_step}"
        end
      end

      def parse_bnode_config(bnode_config)
        subject_name = bnode_name
        @subject_object_map[@subject_name_stack.last] << subject_name
        parse_subject_config(subject_name, bnode_config)
      end

      def process_source_macro(method_def, variable_name)
        args = method_def[:args_].keys.map do |hash|
          if hash == :arg_
            method_def[:args_][:arg_].to_s[1..-2]
          else
            value = hash.values.first
            if value.is_a?(Parslet::Slice)
              value.to_s[1..-2]
            elsif value.is_a?(Hash)
              value.values.first.to_s
            else
              value.to_s
            end
          end
        end

        if args[1].to_s == 'duckdb'
          process_source_macro_for_rdb(args, variable_name)
        else
          @target_source_file_path = source_file_path(args[0])
          add_source_subject_map(@target_source_file_path, variable_name)
          @source_format_map[@target_source_file_path] = [] unless @source_format_map.key?(@target_source_file_path)
          @source_format_map[@target_source_file_path] << args[1] if args[1]
        end
      end

      # source_macro_args: [rdb_file_path, rdb_type (ex. duckdb), table_name]
      def process_source_macro_for_rdb(source_macro_args, variable_name)
        @target_source_file_path = source_file_path([source_macro_args[0], source_macro_args[2]].join('.'))
        add_source_subject_map(@target_source_file_path, variable_name)
        @source_format_map[@target_source_file_path] = [] unless @source_format_map.key?(@target_source_file_path)
        @source_format_map[@target_source_file_path] << source_macro_args[1] if source_macro_args[1]
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
        @subject_converts[subject_name] << convert
      end

      def add_object_convert(subject_name, object_name, convert)
        @object_converts[subject_name] = {} unless @object_converts.key?(subject_name)
        if @object_converts[subject_name].key?(object_name)
          @object_converts[subject_name][object_name] << convert
        else
          @object_converts[subject_name][object_name] = [ convert ]
        end
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
    end
  end
end
