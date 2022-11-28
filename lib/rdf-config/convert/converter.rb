class RDFConfig
  class Convert
    class Converter
      def initialize(convert_method)
        @convert_method = convert_method
        @target_value = []
      end

      def convert_row(row)
        converted_value = {}
        @convert_method.each do |variable_name, methods|
          @target_value = row
          exec_convert_process(methods)
          converted_value[variable_name] = @target_value
        end

        converted_value
      end

      def exec_convert_process(methods)
        methods.each do |method|
          unless respond_to?(method[:method_name_])
            require_relative "../converters/#{method[:method_name_]}.rb"
            self.class.define_method(
              method[:method_name_].to_sym, self.class.instance_method(method[:method_name_].to_sym)
            )
          end

          args = if method.key?(:args_)
                   case method[:args_]
                   when Hash
                     [arg_value(method[:args_][:arg_])]
                   when Array
                     method[:args_].map { |arg| arg_value(arg[:arg_]) }
                   else
                     []
                   end
                 else
                   []
                 end

          exec_converter(method[:method_name_], *args)
        end
      end

      def exec_converter(name, *args)
        @target_value = if @target_value.is_a?(Array)
                          @target_value.map { |v| call_convert_method(name, v, *args) }
                        else
                          call_convert_method(name, @target_value, *args)
                        end
      end

      def call_convert_method(method_name, target_value, *args)
        if target_value.to_s.empty?
          ''
        else
          send(method_name, target_value, *args)
        end
      end

      def arg_value(parslet_slice)
        value = parslet_slice.to_str
        if value =~ /\A\d+\z/
          value.to_i
        elsif value[0] == '"' || value[0] == "'"
          value[1..-2]
        else
          value
        end
      end
    end
  end
end
