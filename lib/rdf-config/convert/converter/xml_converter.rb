# frozen_string_literal: true

require_relative '../converter'

class RDFConfig
  class Convert
    class XMLConverter < Converter
      MACRO_NAME = 'xml'
      PATH_SEPARATOR = '/'

      def initialize(convert_method, macro)
        super

        @element = nil
      end

      def exec_converter(method_def, *args)
        name = method_def[:method_name_]
        return if name == ROOT_MACRO_NAME

        target_value = if !args.empty? && args[0][0] == '@'
                         @element
                       else
                         @converted_values.last
                       end

        if target_value.is_a?(Array)
          target_value.map { |v| call_convert_method(name, v, *args) }
        else
          call_convert_method(name, target_value, *args)
        end
      end

      def exec_method(method_def)
        super
        return unless method_def[:method_name_] == MACRO_NAME

        @element = if method_def[:variable_name].nil?
                     @converted_values.pop
                   else
                     @variable[method_def[:variable_name]]
                   end
        xpath = method_def[:args_][:arg_][1..-2]
        last_separator_pos = xpath.rindex('/')
        target = if last_separator_pos.nil?
                   xpath
                 else
                   xpath[last_separator_pos + 1..-1]
                 end
        converted_value = case target
                          when 'text()'
                            @element&.text
                          else
                            @element&.attribute(target[1..-1]).value
                          end
        converted_value = converted_value.to_s

        if method_def[:variable_name].nil?
          @converted_values << converted_value
        else
          @variable[method_def[:variable_name]] = converted_value
        end
      end

      def macro_names
        [MACRO_NAME]
      end

      def path_separator
        PATH_SEPARATOR
      end
    end
  end
end
