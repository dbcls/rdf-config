# frozen_string_literal: true

require_relative '../rdf_generator'

class RDFConfig
  class Convert
    class JSON2RDF < RDFGenerator
      private

      def path_by_convert_def(subject_name)
        root_def = @convert.convert_method[subject_name].select { |method_def| method_def[:method_name_] == ROOT_MACRO_NAME }.first

        path = root_def[:args_][:arg_][1..-2]
        path = path[1..] if path[0] == '.'

        path
      end
    end
  end
end
