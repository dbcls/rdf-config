class RDFConfig
  class Convert
    class JSONConverter < Converter
      def exec_converter(name, *args)
        if name == 'json'
          keys = args[0].split(/\s*\.\s*/)
          if keys.size > 2
            key_path = args[0].split(/\s*\.\s*/)[1..-2]
            target_value = eval("#{@target_value}#{key_path}")
          else
            target_value = @target_value
          end
          args = [keys.last]
        else
          target_value = @target_value
        end

        @target_value = if target_value.is_a?(Array)
                          target_value.map { |v| call_convert_method(name, v, *args) }
                        else
                          call_convert_method(name, target_value, *args)
                        end
      end
    end
  end
end
