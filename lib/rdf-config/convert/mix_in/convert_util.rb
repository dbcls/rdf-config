# frozen_string_literal: true

require 'uri'
require_relative '../parser/string_parser'

class RDFConfig
  class Convert
    module MixIn
      module ConvertUtil
        def to_bool(value)
          !['0', 'f', 'false', 'n', 'no', 'off', ''].include?(value.to_s.strip.downcase)
        end

        def source_type_for(source)
          file_ext = ext_by_file_path(source)

          type_value_for(file_ext)
        end

        def ext_by_file_path(file_path)
          ext = File.extname(file_path)
          ext = ext[1..-1] if ext.to_s.size.positive?

          ext.to_s.downcase
        end

        def type_value_for(type_value)
          type_value = type_value.to_s
          if DUCKDB_FILE_EXTENSIONS.include?(type_value)
            DUCKDB_FILE_EXTENSIONS.first
          elsif SQLITE3_FILE_EXTENSIONS.include?(type_value)
            SQLITE3_FILE_EXTENSIONS.first
          elsif TABLE_FORMATS.include?(type_value)
            type_value
          else
            UNKNOWN_SOURCE_TYPE
          end
        end

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
          source[0]
        end

        def rdb_source_table(source)
          source[1]
        end
      end
    end
  end
end
