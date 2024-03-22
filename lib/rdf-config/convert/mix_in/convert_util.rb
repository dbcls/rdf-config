# frozen_string_literal: true

require 'uri'

class RDFConfig
  class Convert
    module MixIn
      module ConvertUtil
        def convert_variable?(variable_name)
          variable_name.start_with?('$')
        end

        def ext_by_file_path(file_path)
          ext = File.extname(file_path)
          ext = ext[1..] if ext.to_s.size.positive?

          ext
        end

        def extract_rdf_datatype(str)
          return nil unless str.is_a?(String)

          /.+['"]\^\^(?<datatype>.+)\z/ =~ str

          datatype
        end

        def prefix_by_uri(uri)
          uri = URI.parse(uri)

          uri.scheme
        rescue
          nil
        end
      end
    end
  end
end
