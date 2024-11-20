# frozen_string_literal: true
require_relative '../converter'

class RDFConfig
  class Convert
    class JSONConverter < Converter
      MACRO_NAME = 'json'
      PATH_SEPARATOR = '.'

      def exec_converter(method_def, *args)
        name = method_def[:method_name_]
        if name == MACRO_NAME
          keys = args[0].split(PATH_SEPARATOR)
          args = [keys.last]
        end

        if method_def[:variable_name].nil?
          target_value = @target_value

          @target_value = if target_value.is_a?(Array)
                            target_value.map { |v| call_convert_method(name, v, *args) }
                          else
                            call_convert_method(name, target_value, *args)
                          end
        else
          @variable[method_def[:variable_name]] = call_convert_method(name, target_row, *args)
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
