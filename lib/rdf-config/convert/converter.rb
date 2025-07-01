# frozen_string_literal: true

require_relative 'processor/switch_processor'

class RDFConfig
  class Convert
    class Converter
      ROW_TARGET_METHODS = %w[csv json xml].freeze
      # VARIABLE_REGEXP = /\$\{([a-zA-Z]\w*)\}|\$([a-z_]\w+)\W*/
      VARIABLE_REGEXP = /\$[a-z_]\w+/
      NOT_MAP_METHOS = %w[pick]

      attr_accessor :convert_variable_names
      attr_reader :target_value

      def initialize(convert_method, macro)
        @convert_method = convert_method
        @macro = macro

        @target_value = []
        @converted_values = []
        @target_rows = []
        @variable = {}
      end

      def convert_value(row, converts)
        @element = row
        @target_value = row
        @converted_values.clear

        # variable_name = converts.keys.first
        # converts[variable_name].each do |method_def|
        converts.each do |method_def|
          if method_def.is_a?(Processor::SwitchProcessor)
            method_def.process(self)
            next
          end

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
          if @target_value.is_a?(Array) && !NOT_MAP_METHOS.include?(method_name)
            @target_value.map { |v| call_convert_method(method_name, v, *args) }
          else
            call_convert_method(method_name, @target_value, *args)
          end
        elsif @variable.key?(variable_name)
          call_convert_method(method_name, @variable[variable_name], *args)
        else
          call_convert_method(method_name, @target_value.empty? ? target_row : @target_value, *args)
        end
      end

      def call_convert_method(method_name, target_value, *args)
        #--> unless respond_to?(method_name.to_sym)
        #-->   require_relative "#{MACRO_DIR_NAME}/#{method_name}"
        #-->   self.class.define_method(
        #-->     method_name.to_sym, self.class.instance_method(method_name.to_sym)
        #-->   )
        #--> end

        if target_value.to_s.empty?
          ''
        else
          if ROW_TARGET_METHODS.include?(method_name)
            @macro.send(method_name, target_row, *args)
          else
            @macro.send(method_name, target_value, *args)
          end
        end
      end

      def expand_variable(variable)
        variable.to_s.gsub(VARIABLE_REGEXP) do |matched|
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

      def clear_target_rows
        @target_rows.clear
      end

      def push_target_row(row, clear_variable: false)
        @variable.clear if clear_variable

        @target_rows.push(row)
      end

      def pop_target_row
        @target_rows.pop
      end

      def converter_variable?(variable_name)
        variable_name.to_s.start_with?('$')
      end

      def target_row
        @target_rows.last
      end

      def variable_value(variable_name)
        @variable[variable_name]
      end
    end
  end
end
