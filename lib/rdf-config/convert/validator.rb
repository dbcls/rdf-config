# frozen_string_literal: true

require_relative '../validator'

class RDFConfig
  class Convert
    class Validator < RDFConfig::Validator
      def initialize(config, **opts)
        super
        @convert = opts[:convert]
      end

      def validate
        validate_variable_name
        validate_exist_source
        validate_source_file_path
        validate_macro_name
        validate_convert_variable_name

        raise InvalidConfig, format_error_message if error?
      end

      private

      def validate_variable_name
        @convert.convert_method.each_key do |variable_name|
          if !variable_name.is_a?(String) || @convert.bnode_name?(variable_name) || variable_name[0] == '$' || model_variable_names.include?(variable_name)
            next
          end

          add_error(%(Variable name "#{variable_name}" does not exist in model.yaml.))
        end
      end

      def validate_exist_source
        @convert.subject_config.each do |subject_name, subject_configs|
          next if subject_configs.first.start_with?(SOURCE_MACRO_NAME)

          add_error(%(The source must be set for the subject "#{subject_name}".))
        end
      end

      def validate_source_file_path
        @convert.source_subject_map.each_key do |file_path|
          add_error(%(Source file "#{file_path}" does not exist.)) unless File.exist?(file_path)
        end
      end

      def validate_macro_name
        @convert.macro_names.each do |macro_name|
          next if SYSTEM_MACRO_NAMES.include?(macro_name)

          macro_file_path = File.join(__dir__, MACRO_DIR_NAME, "#{macro_name}.rb")
          next if File.exist?(macro_file_path)

          add_error(%(Macro "#{macro_name}" is not defined.))
        end
      end

      def validate_convert_variable_name
        @convert.convert_variable_names.each do |variable_name|
          next if valid_variable_name?(variable_name)

          add_error(%(Variable name "#{variable_name}" is invalid. Variable name must begin with $ and must not contain any characters other than uppercase, lowercase, underscore, and numbers.))
        end
      end

      def valid_variable_name?(variable_name)
        /\A\$[a-z]\w+\z/ =~ variable_name
      end

      def format_error_message
        @errors.map { |error| "  * #{error}" }.unshift('ERROR:').join("\n")
      end
    end
  end
end
