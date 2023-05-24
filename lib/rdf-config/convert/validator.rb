# frozen_string_literal: true

require_relative '../validator'
require_relative 'method_parser'

class RDFConfig
  class Convert
    class Validator < RDFConfig::Validator
      attr_reader :convert_method, :source_file_format

      def initialize(config, **opts)
        super

        @convert_method = {}
        @source_file_format = nil

        @convert = opts[:convert]
        @method_parser = MethodParser.new
        @macro_names = []
        @root_path = nil
      end

      def validate
        validate_variable_name
        validate_all_subject_config
        validate_all_object_config
        validate_macro_name

        @convert_method.each_key do |variable_name|
          method_defs = []
          @convert_method[variable_name].each do |method_def|
            if method_def[:method_name_] == ROOT_MACRO_NAME
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
          @convert_method[variable_name] = method_defs
        end

        raise InvalidConfig, errors.join("\n") if error?
      end

      private

      def validate_variable_name
        (@convert.subject_config.keys + @convert.object_config.keys).each do |variable_name|
          if !variable_name.is_a?(String) || @convert.bnode_name?(variable_name) || variable_name[0] == '$' || model_variable_names.include?(variable_name)
            next
          end

          add_error(%(ERROR: Variable name "#{variable_name}" in convert.yaml does not exist in model.yaml."))
        end
      end

      def validate_all_subject_config
        @convert.subject_config.each do |subject_name, subject_config|
          validate_subject_config(subject_name, subject_config)
        end
      end

      def validate_subject_config(subject_name, configs)
        @convert_method[subject_name] = [] unless @convert_method.key?(subject_name)
        configs.each do |convert_config|
          @convert_method[subject_name] << parse_converter(subject_name, convert_config)
        end
      end

      def validate_all_object_config
        @convert.object_config.each do |object_name, configs|
          validate_object_config(object_name, configs)
        end
      end

      def validate_object_config(object_name, configs)
        configs.each do |convert_config|
          next if convert_config.is_a?(Hash) && convert_config.keys.first.to_s == '_subject_name'

          @convert_method[object_name] = [] unless @convert_method.key?(object_name)
          @convert_method[object_name] << parse_converter(object_name, convert_config)
        end
      end

      def validate_config
        @config.convert.each do |subject_name, convert_configs|
          convert_configs.each do |convert_config|
            if convert_config.is_a?(Hash) && convert_config.key?('variables')
              # RDF object
              convert_config['variables'].each do |variable_config|
                variable_name = variable_config.keys.first
                @convert_method[variable_name] = [] unless @convert_method.key?(variable_name)

                converters = if variable_config[variable_name].is_a?(Array)
                               variable_config[variable_name]
                             else
                               [variable_config[variable_name]]
                             end
                converters.each do |converter|
                  @convert_method[variable_name] << parse_converter(variable_name, converter)
                end
              end
            else
              # RDF subject
              @convert_method[subject_name] = [] unless @convert_method.key?(subject_name)
              @convert_method[subject_name] << parse_converter(subject_name, convert_config)
            end
          end
        end
      end

      def parse_converter(variable_name, converter)
        if converter.is_a?(Hash)
          convert_variable_name = converter.keys.first
          converter = converter[convert_variable_name]
          unless valid_variable_name?(convert_variable_name)
            add_error(%(ERROR: Invalid variable "#{convert_variable_name}". Variable must begin with $ and must not contain any characters other than uppercase, lowercase, underscore, and numbers.))
          end
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
        add_macro_name(method_def[:method_name_].to_s)

        if @source_file_format.nil? && SOURCE_FORMATS.include?(method[:method_name_])
          @source_file_format = method[:method_name_]
        end

        method_def
      end

      def validate_macro_name
        @macro_names.each do |macro_name|
          next if macro_name == ROOT_MACRO_NAME

          macro_file_path = File.join(__dir__, MACRO_DIR_NAME, "#{macro_name}.rb")
          next if File.exist?(macro_file_path)

          add_error(%(ERROR: Macro "#{macro_name}" is not defined.))
        end
      end

      def add_macro_name(macro_name)
        @macro_names << macro_name unless @macro_names.include?(macro_name)
      end

      def valid_variable_name?(variable_name)
        /\A\$[a-z]\w+\z/ =~ variable_name
      end
    end
  end
end
