# frozen_string_literal: true

require_relative '../mix_in/convert_util'

class RDFConfig
  class Convert
    class Processor
      class SwitchProcessor
        include MixIn::ConvertUtil

        def initialize(variable_name, method, convert_process)
          @variable_name = variable_name
          @method_arg = if method =~ /\Aswitch\s*\((.+)\s*\)\z/
                          parse_quoted_string(Regexp.last_match(1))
                        end
          @convert_process = convert_process

          @method_defs = {}
        end

        def parse_convert_process(config_parser)
          @convert_process.each do |case_value, convert_processes|
            case_value = if case_value.to_s == 'default' && !case_value.quoted?
                           :default
                         else
                           case_value.to_s
                         end
            @method_defs[case_value] = []
            Array(convert_processes).each do |convert_process|
              @method_defs[case_value] << config_parser.parse_converter(@variable_name, convert_process)
            end
          end
        end

        def process(converter)
          method_defs(converter).each do |method_def|
            converter.exec_method(method_def)
          end
        end

        def method_defs(converter)
          cur_val = current_value(converter)
          if @method_defs.key?(cur_val)
            @method_defs[cur_val]
          elsif @method_defs.key?(:default)
            @method_defs[:default]
          else
            []
          end
        end

        def current_value(converter)
          if convert_variable?(@method_arg)
            converter.variable_value(@method_arg)
          elsif @method_arg
            converter.target_row[@method_arg]
          else
            target_value = converter.target_value
            if target_value.is_a?(Array)
              target_value.last
            else
              target_value
            end
          end
        end
      end
    end
  end
end
