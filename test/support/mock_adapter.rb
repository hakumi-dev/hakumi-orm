# typed: false
# frozen_string_literal: true

module HakumiORM
  module Test
    class MockResult < HakumiORM::Adapter::Result
      attr_reader :data

      def initialize(data, affected: nil)
        @data = data
        @affected = affected || data.length
      end

      def row_count = @data.length

      def get_value(row, col) = @data[row]&.[](col)

      def values = @data

      def column_values(col) = @data.map { |r| r[col] }

      def affected_rows = @affected

      def close = nil
    end

    class MockAdapter < HakumiORM::Adapter::Base
      attr_reader :executed_queries, :dialect

      def initialize(dialect: nil)
        @dialect = dialect || HakumiORM::Dialect::Postgresql.new
        @executed_queries = []
        @results = {}
        @default_result = MockResult.new([])
      end

      def stub_result(sql_pattern, data, affected: nil)
        @results[sql_pattern] = MockResult.new(data, affected: affected)
      end

      def stub_default(data, affected: nil)
        @default_result = MockResult.new(data, affected: affected)
      end

      def exec_params(sql, params)
        @executed_queries << { sql: sql, params: params }
        find_result(sql)
      end

      def exec(sql)
        @executed_queries << { sql: sql, params: [] }
        find_result(sql)
      end

      def close = nil

      def last_sql
        @executed_queries.last&.dig(:sql)
      end

      def last_params
        @executed_queries.last&.dig(:params)
      end

      def reset!
        @executed_queries.clear
      end

      private

      def find_result(sql)
        @results.each do |pattern, result|
          return result if sql.include?(pattern)
        end
        @default_result
      end
    end
  end
end
