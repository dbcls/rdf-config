require 'csv'

class RDFConfig
  class Convert
    class JSONReader
      def initialize(source_file)
        @source_file = source_file
        @data = JSON.parse(File.read(@source_file))
      end

      def read(key)
        @data[key]
      end
    end
  end
end
