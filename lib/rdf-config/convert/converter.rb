# frozen_string_literal: true

class RDFConfig
  class Convert
    class Converter
      def initialize(convert_method)
        @convert_method = convert_method
        @target_value = []
        @converted_values = []
        @target_rows = []
        @variable = {}
      end

      def convert_value(row, variable_name)
        @element = row
        @target_value = row
        @converted_values << row
        @convert_method[variable_name].each do |method_def|
          next if SYSTEM_MACRO_NAMES.include?(method_def[:method_name_])

          exec_method(method_def)
        end

        @converted_values.last
      end

      def exec_method(method_def)
        if !method_def[:method_name_].nil? && respond_to?(method_def[:method_name_])
          require_relative "#{MACRO_DIR_NAME}/#{method_def[:method_name_]}"
          self.class.define_method(
            method_def[:method_name_].to_sym, self.class.instance_method(method_def[:method_name_].to_sym)
          )
        end

        args = if method_def.key?(:args_)
                 case method_def[:args_]
                 when Hash
                   if method_def[:args_].size == 1
                     [arg_value(method_def[:args_][:arg_])]
                   else
                     method_def[:args_].keys.map { |arg| arg_value(arg[:arg_]) }
                   end
                 when Array
                   method_def[:args_].map { |arg| arg_value(arg[:arg_]) }
                 else
                   []
                 end
               else
                 []
               end
        args.map! { |arg| expand_variable(arg) }

        value = exec_converter(method_def, *args)
        if method_def[:variable_name].nil?
          @target_value = value
          @converted_values << value
        else
          @variable[method_def[:variable_name]] = value
        end
      end

      def exec_converter(method_def, *args)
        method_name = method_def[:method_name_]
        variable_name = method_def[:variable_name]
        if variable_name.nil?
          if @target_value.is_a?(Array)
            @target_value.map { |v| call_convert_method(method_name, v, *args) }
          else
            call_convert_method(method_name, @target_value, *args)
          end
        else
          call_convert_method(method_name, target_row, *args)
        end
      end

      def call_convert_method(method_name, target_value, *args)
        unless respond_to?(method_name.to_sym)
          require_relative "#{MACRO_DIR_NAME}/#{method_name}"
          self.class.define_method(
            method_name.to_sym, self.class.instance_method(method_name.to_sym)
          )
        end

        if target_value.to_s.empty?
          ''
        else
          send(method_name, target_value, *args)
        end
      end

      def expand_variable(str)
        str.gsub(/\$[a-z_]\w+/) do |matched|
          if @variable.keys.include?(matched)
            @variable[matched]
          else
            matched
          end
        end
      end

      def arg_value(arg)
        value = arg.to_s
        if value =~ /\A\d+\z/
          value.to_i
        elsif value[0] == '"' || value[0] == "'"
          value[1..-2]
        else
          value
        end
      end

      def clear_value
        @target_value = nil
      end

      def push_target_row(row)
        @target_rows.push(row)
      end

      def pop_target_row
        @target_rows.pop
      end

      def convert_variable_names
        @convert_variable_names ||= @convert_method.keys.select { |name| name[0][0] == '$' }
      end

      def target_row
        @target_rows.last
      end
    end
  end
end
