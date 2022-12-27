# frozen_string_literal: true
require_relative '../converter'

class RDFConfig
  class Convert
    class CSVConverter < Converter
      def macro_names
        %w[csv tsv]
      end

      # def set_path_variable_map; end
      def set_paths
        @paths = @path_variable_map.keys
        @root_paths = @paths
      end

      def set_path_relation; end
    end
  end
end
