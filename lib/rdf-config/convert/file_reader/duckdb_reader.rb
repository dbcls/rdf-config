# frozen_string_literal: true

require 'duckdb'

class RDFConfig
  class Convert
    class DuckdbReader
      QUERY_LIMIT = 10

      class << self
        def valid_db_file?(db_path)
          db_path_is_duckdb = File.open(db_path, 'rb') do |f|
            if f.size < 16
              false
            else
              header = f.read(4)
              header == "DUCK".b
            end
          end

          return false unless db_path_is_duckdb

          DuckDB::Database.open(db_path) do |db|
            conn = db.connect
            conn.query("SELECT 1")
            true
          end
        rescue DuckDB::Error
          false
        end

        def table_exist?(db_path, table_name)
          table_is_exist = false
          DuckDB::Database.open(db_path) do |db|
            conn = db.connect
            result = conn.query("SELECT COUNT(*) AS cnt FROM information_schema.tables WHERE table_name = ?", table_name)
            table_is_exist = result.first[0] > 0
          end

          table_is_exist
        end
      end

      def initialize(source_file, table_name)
        @source_file = source_file
        @table_name = table_name

        @db = nil
        @conn = nil
        @column_name = {}

        connect
      end

      def each_row(&block)
        columns = column_names(@table_name).map { |col_name| escape_duckdb_identifier(col_name) }.join(',')
        offset = 0
        loop do
          query = "SELECT #{columns} FROM #{@table_name} OFFSET #{offset} LIMIT #{QUERY_LIMIT}"
          result = @conn.query(query)
          rows = result.to_a
          break if rows.empty?

          rows.each do |row|
            block.call(row_hash(@table_name, row))
          end

          offset += QUERY_LIMIT
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

      def escape_duckdb_identifier(identifier)
        # nil や空文字は許可しない（SQL構文エラー防止）
        raise ArgumentError, "Identifier cannot be nil or empty" if identifier.nil? || identifier.to_s.strip.empty?

        str = identifier.to_s
        # 内部の二重引用符をエスケープ
        escaped = str.gsub('"', '""')
        # 前後を二重引用符で囲む
        "\"#{escaped}\""
      end

      def escape_duckdb_qualified_name(*parts)
        parts.map { |p| escape_duckdb_identifier(p) }.join('.')
      end

      def disconnect
        @conn.close unless @conn.nil?
        @db.close unless @db.nil?
      end
    end
  end
end
