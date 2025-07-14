# frozen_string_literal: true

require 'duckdb'

class RDFConfig
  class Convert
    class DuckdbReader
      def initialize(source_file, table_name)
        @source_file = source_file
        @table_name = table_name
        @db = nil
        @conn = nil
        @column_name = {}

        connect
        @result = @conn.query("SELECT * FROM #{@table_name}")
      end

      def each_row(&block)
        @result.each do |row|
          block.call(row_hash(@table_name, row))
        end
        disconnect
      end

      def source
        @table_name
      end

      private

      def connect
        @db = DuckDB::Database.open(@source_file)
        @conn = @db.connect
      end

      def table_names
        result = @conn.query('PRAGMA show_tables;')

        result.map(&:first)
      end

      def column_names(table_name)
        return @column_name[table_name] if @column_name.key?(table_name)

        result = @conn.query("PRAGMA table_info('#{table_name}');")
        columns = result.columns.map(&:name)
        name_column_index = columns.index('name')

        @column_name[table_name] = result.map { |row| row[name_column_index] }
      end

      def row_hash(table_name, row)
        column_names(table_name).zip(row).to_h
      end

      def disconnect
        @conn.close unless @conn.nil?
        @db.close unless @db.nil?
      end
    end
  end
end
