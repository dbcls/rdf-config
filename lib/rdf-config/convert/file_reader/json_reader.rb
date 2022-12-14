require 'csv'

class RDFConfig
  class Convert
    class JSONReader
      def initialize(source_file)
        @source_file = source_file
        @data = JSON.parse(File.read(@source_file))
      end

      def read(key)
        keys = key.split(/\s*\.\s*/)
        if keys.size == 1
          @data[key]
        else
          key_path = keys.map { |k| "['#{k}']" }
          eval "@data#{key_path[0..-2].join}"
        end
      end
    end
  end
end
