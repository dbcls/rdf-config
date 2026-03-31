# frozen_string_literal: true

require 'sqlite3'

class RDFConfig
  class Convert
    class SQLite3Reader
      QUERY_LIMIT = 10

      class << self
        def valid_db_file?(db_path)
          SQLite3::Database.open(db_path) do |db|
            db.execute("SELECT 1")
            true
          end
        rescue SQLite3::Exception
          false
        end

        def table_exist?(db_path, table_name)
          table_is_exist = false
          SQLite3::Database.open(db_path) do |db|
            db.results_as_hash = true
            result = db.execute("SELECT COUNT(*) AS cnt FROM sqlite_master WHERE type = 'table' AND name = ?", [table_name])
            table_is_exist = result.first['cnt'] > 0
          end

          table_is_exist
        end
      end

      def initialize(source_file, table_name)
        @source_file = source_file
        @table_name = table_name

        @db = nil

        connect
      end

      def each_row(&block)
        offset = 0
        loop do
          query = "SELECT * FROM #{@table_name} LIMIT #{QUERY_LIMIT} OFFSET #{offset}"
          rows = @db.execute(query)
          break if rows.empty?

          rows.each do |row|
            block.call(row)
          end

          offset += QUERY_LIMIT
        end

        disconnect
      end

      def connect
        @db = SQLite3::Database.new(@source_file)
        @db.results_as_hash = true
      end

      def disconnect
        @db.close unless @db.nil?
      end
    end
  end
end
