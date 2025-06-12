# frozen_string_literal: true

require 'uri'
require_relative '../parser/string_parser'

class RDFConfig
  class Convert
    module MixIn
      module ConvertUtil
        def parse_quoted_string(quoted_string)
          return quoted_string unless ['"', "'"].include?(quoted_string[0])

          parser = StringParser.new
          tree = parser.parse(quoted_string)
          # tree[:string][:chars].map { |hash| hash[:char].str }.join

          transform = StringTransform.new
          result = transform.apply(tree)

          result[:string]
        end

        def convert_variable?(variable_name)
          variable_name.to_s.start_with?('$')
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

        def rdb_source_file(source)
          source.split('.')[0..-2].join('.')
        end

        def rdb_source_table(source)
          source.split('.').last
        end
      end
    end
  end
end
