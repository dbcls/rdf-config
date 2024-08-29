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
        # validate_exist_source
        validate_source_file_path
        validate_source_format
        validate_macro_name
        validate_convert_variable_name

        raise InvalidConfig, format_error_message if error?
      end

      def format_error_message
        @errors.map { |error| "  * #{error}" }.unshift('ERROR:').join("\n")
      end

      private

      def validate_variable_name
        @convert.variable_names.each do |variable_name|
          if !variable_name.is_a?(String) || @convert.bnode_name?(variable_name) || variable_name[0] == '$' || model_variable_names.include?(variable_name)
            next
          end

          add_error(%(Variable name "#{variable_name}" does not exist in model.yaml.))
        end
      end

      def validate_exist_source
        @convert.subject_converts.each do |subject_convert|
          subject_convert.each do |subject_name, subject_configs|
            next if subject_configs.first[:method_name_].start_with?(SOURCE_MACRO_NAME)

            add_error(%(The source must be set for the subject "#{subject_name}".))
          end
        end
      end

      def validate_source_file_path
        @convert.source_subject_map.each_key do |file_path|
          if file_path.nil?
            add_error(%(#{@convert.source_subject_map[nil].join(', ')}: Since source file is not specified in convert.yaml, please specify the source file in the --convert option.))
          elsif !File.exist?(file_path)
            add_error(%(Source file "#{file_path}" does not exist.))
          end
        end
      end

      def validate_source_format
        @convert.source_format_map.each do |source_file_path, formats|
          next unless formats.is_a?(Array)

          if formats.empty?
            add_error("There is no file format specification for the source file (#{source_file_path}) in the settings in convert.yaml.")
          elsif formats.size > 1
            add_error("In the settings in convert.yaml, there are multiple file format specifications (#{formats.join(', ')}) for the same source file (#{source_file_path}) .")
          end
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
    end
  end
end
