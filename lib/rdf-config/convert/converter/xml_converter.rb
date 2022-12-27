# frozen_string_literal: true
require_relative '../converter'

class RDFConfig
  class Convert
    class XMLConverter < Converter
      MACRO_NAME = 'xml'
      PATH_SEPARATOR = '/'
      XPATH_REGEXP = %r{\A(/.+)/(@[\w-]+|[\w-]+/text\(\))\z}

      def exec_converter(name, *args)
        target_value = @target_value
        if name == MACRO_NAME
          XPATH_REGEXP =~ args[0]
          if ::Regexp.last_match(2).end_with?('/text()')
            args = ['text', ::Regexp.last_match(2).split('/').first]
          elsif ::Regexp.last_match(2)[0] == '@'
            args = ['attribute', ::Regexp.last_match(2)[1..]]
          end
        end

        @target_value = if target_value.is_a?(Array)
                          target_value.map { |v| call_convert_method(name, v, *args) }
                        else
                          call_convert_method(name, target_value, *args)
                        end
      end

      def extract_path(path)
        path_regexp =~ path

        ::Regexp.last_match(1)
      end

      def macro_names
        [MACRO_NAME]
      end

      def path_separator
        PATH_SEPARATOR
      end

      def path_regexp
        XPATH_REGEXP
      end
    end
  end
end
