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
        @typed = T.let(false, T::Boolean)
        @values_cache = T.let(nil, T.nilable(T::Array[T::Array[CellValue]]))
      end

      sig { params(type_map: PG::TypeMapByColumn).void }
      def apply_type_map!(type_map)
        return if @typed

        @pg_result.map_types!(type_map)
        @typed = true
        @values_cache = nil
      end

      sig { override.returns(Integer) }
      def row_count
        @pg_result.ntuples
      end

      sig { override.params(row: Integer, col: Integer).returns(CellValue) }
      def get_value(row, col)
        @pg_result.getvalue(row, col)
      end

      sig { override.returns(T::Array[T::Array[CellValue]]) }
      def values
        cached = @values_cache
        return cached if cached

        vals = @pg_result.values
        @values_cache = vals
        vals
      end

      sig { override.params(col: Integer).returns(T::Array[CellValue]) }
      def column_values(col)
        @pg_result.column_values(col)
      end

      sig { override.returns(Integer) }
      def affected_rows
        @pg_result.cmd_tuples
      end

      sig { override.void }
      def close
        @values_cache = nil
        @pg_result.clear
      end
    end
  end
end
