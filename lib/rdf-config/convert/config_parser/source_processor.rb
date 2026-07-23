# frozen_string_literal: true

require_relative '../../convert'
require_relative '../mix_in/convert_util'

class RDFConfig
  class Convert
    class ConfigParser
      class SourceProcessor
        include MixIn::ConvertUtil

        attr_reader :source, :source_type, :rdb_table_name, :errors

        def initialize
          @source = nil
          @source_type = nil
          @rdb_table_name = nil

          @errors = []
        end

        def parse_method_def(method_def)
          method_def[:args_].keys.map do |hash|
            if hash == :arg_
              method_def[:args_][:arg_].to_s[1..-2]
            else
              value = hash.values.first
              if value.is_a?(Parslet::Slice)
                value.to_s[1..-2]
              elsif value.is_a?(Hash)
                if value.keys.first.to_s == 'symbol'
                  value.values.first.to_sym
                else
                  value.values.first.to_s
                end
              else
                value.to_s
              end
            end
          end
        end

        def parse_args(*source_macro_args)
          @source = source_macro_args.shift
          case source_macro_args.size
          when 0
            @source_type = source_type_for(@source)
            add_error(invalid_source_extension_error) if unknown_source_type?
          when 1
            arg = source_macro_args.shift
            if arg.is_a?(Symbol)
              @source_type = type_value_for(arg)
              add_error(invalid_file_type_error(arg)) if unknown_source_type?
            else
              @source_type = source_type_for(@source)
              add_error(invalid_source_extension_error) if unknown_source_type?
              @rdb_table_name = arg
            end
          else
            @source_type = type_value_for(source_macro_args[0])
            add_error(invalid_file_type_error(source_macro_args[0])) if unknown_source_type?
            @rdb_table_name = source_macro_args[1].to_s
          end
        end

        def validate
          if @source_type == 'duckdb'
            require_relative '../file_reader/duckdb_reader'
            add_error(not_found_table_error) unless DuckdbReader.table_exist?(@source, @rdb_table_name)
          elsif @source_type == 'sqlite3'
            begin
              require_relative '../file_reader/sqlite3_reader'
              add_error(not_found_table_error) unless SQLite3Reader.table_exist?(@source, @rdb_table_name)
            rescue SQLite3::NotADatabaseException
              add_error(%Q(Database file "#{@source}" does not SQLite3 database file))
            end
          end
        end

        def source_is_rdb?
          RDB_FILE_EXTENSIONS.include?(@source_type)
        end

        def error?
          !@errors.empty?
        end

        private

        def unknown_source_type?
          @source_type == 'unknown'
        end

        def add_error(msg)
          @errors << msg
        end

        def source_not_found_error
          %Q(Source file "#{@source}" does not exist.")
        end

        def invalid_source_extension_error
          'Unable to determine the file type from the source file extension.'
        end

        def invalid_file_type_error(type_value)
          %Q/File type #{type_value.inspect} is invalid. Valid file types are #{VALID_SOURCE_TYPES.map(&:inspect).join(', ')}/
        end

        def not_found_table_error
          %Q(Table "#{@rdb_table_name}" does not exist in database "#{@source}")
        end
      end
    end
  end
end
