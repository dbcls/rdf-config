# frozen_string_literal: true

require_relative '../validator'
require_relative 'mix_in/convert_util'
require_relative 'json_ld_generator/csv2json_lines'

class RDFConfig
  class Convert
    class Validator < RDFConfig::Validator
      include MixIn::ConvertUtil

      VALID_CONVERT_TYPES = %w[:turtle :ntriples :jsonld :jsonl :context]

      def initialize(config, **opts)
        super
        @convert = opts[:convert]
        @yaml_parser = opts[:yaml_parser]
      end

      def pre_validate
        unless @yaml_parser.nodes_doc.children.size == 1 && @yaml_parser.nodes_doc.children.first.is_a?(Psych::Nodes::Sequence)
          @validator.add_error("#{@yaml_parser.yaml_file} must be an array of conversion settings for each subject.")
          return false
        end

        validate_subjects

        @errors += @yaml_parser.errors

        raise InvalidConfig, format_error_message if error?
      end

      def validate
        validate_convert_type
        validate_context_path if context_mode?
        validate_variable_name
        # validate_exist_source
        validate_source_file_path unless context_mode?
        validate_source_format unless context_mode?
        validate_macro_name
        validate_convert_variable_name

        raise InvalidConfig, format_error_message if error?
      end

      def format_error_message
        @errors.map { |error| "  * #{error}" }.unshift('ERROR:').join("\n")
      end

      private

      def validate_subjects
        subject_names = @yaml_parser.subject_names
        duplicate_subject_names = subject_names.select { |subject_name| subject_names.count(subject_name) > 1 }.uniq

        unless duplicate_subject_names.empty?
          @validator.add_error("Duplicate subject name in convert.yaml: #{duplicate_subject_names.join(', ')}")
        end
      end

      def validate_convert_type
        return if VALID_CONVERT_TYPES.include?(@convert.format)

        add_error(%(Invalid value of --convert option. Valid --convert option values are #{VALID_CONVERT_TYPES.join(', ')}))
      end

      def validate_context_path
        return if @convert.output_path.to_s.strip.empty?

        if File.file?(@convert.output_path)
          validate_output_file_path(@convert.output_path)
        elsif File.directory?(@convert.output_path)
          validate_output_dir_path(@convert.output_path)
        else
          validate_output_file_path(@convert.output_path)
        end
      end

      def validate_output_file_path(output_file_path)
        if File.exist?(output_file_path)
          add_error("Output file: #{output_file_path} already exists.")
        else
          validate_output_dir_path(File.dirname(output_file_path))
        end
      end

      def validate_output_dir_path(output_dir_path)
        if File.exist?(output_dir_path)
          if File.writable?(output_dir_path)
            context_file_path = File.join(output_dir_path, Convert::CSV2JSON_Lines::DEFAULT_CONTEXT_FILE_NAME)
            if File.exist?(context_file_path)
              add_error("Output file: #{context_file_path} already exists.")
            end
          else
            add_error("You do not have write permission for #{output_dir_path}")
          end
        else
          add_error("Output directory: #{output_dir_path} does not exist.")
        end
      end

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
            add_error(%(#{@convert.source_subject_map[nil].join(', ')}: Since source file is not specified in convert.yaml, please specify the source file.))
          else
            formats = @convert.source_format_map[file_path] || []
            file_path = rdb_source_file(file_path) if formats.include?('duckdb')
            add_error(%(Source file "#{file_path}" does not exist.)) unless File.exist?(file_path)
          end
        end
      end

      def validate_source_format
        @convert.source_format_map.each do |source_file_path, formats|
          next unless formats.is_a?(Array)

          if formats.empty?
            add_error("There is no file format specification for the source file (#{source_file_path}) in the settings in convert.yaml.")
          elsif formats.uniq.size > 1
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

      def context_mode?
        %w[:context context].include?(@opts[:format]) || !@convert.output_path.nil?
      end
    end
  end
end
