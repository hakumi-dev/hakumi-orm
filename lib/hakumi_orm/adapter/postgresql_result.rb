# typed: strict
# frozen_string_literal: true

require "pg"

module HakumiORM
  module Adapter
    class PostgresqlResult < Result
      extend T::Sig

      sig { params(pg_result: PG::Result).void }
      def initialize(pg_result)
        @pg_result = T.let(pg_result, PG::Result)
      end

      sig { override.returns(Integer) }
      def row_count
        @pg_result.ntuples
      end

      sig { override.params(row: Integer, col: Integer).returns(T.nilable(String)) }
      def get_value(row, col)
        @pg_result.getvalue(row, col)
      end

      sig { override.returns(T::Array[T::Array[T.nilable(String)]]) }
      def values
        @pg_result.values
      end

      sig { override.params(col: Integer).returns(T::Array[T.nilable(String)]) }
      def column_values(col)
        @pg_result.column_values(col)
      end

      sig { override.returns(Integer) }
      def affected_rows
        @pg_result.cmd_tuples
      end

      sig { override.void }
      def close
        @pg_result.clear
      end
    end
  end
end
