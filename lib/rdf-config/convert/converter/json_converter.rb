# frozen_string_literal: true
require_relative '../converter'

class RDFConfig
  class Convert
    class JSONConverter < Converter
      MACRO_NAME = 'json'.freeze
      PATH_SEPARATOR = '.'.freeze

      def exec_converter(name, *args)
        target_value = @target_value
        if name == 'json'
          keys = args[0].split(PATH_SEPARATOR)
          args = [keys.last]
        end

        @target_value = if target_value.is_a?(Array)
                          target_value.map { |v| call_convert_method(name, v, *args) }
                        else
                          call_convert_method(name, target_value, *args)
                        end
      end

      def extract_path(path)
        last_dot_pos = path.rindex(path_separator)
        if last_dot_pos
          path[0..last_dot_pos - 1]
        else
          path
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
