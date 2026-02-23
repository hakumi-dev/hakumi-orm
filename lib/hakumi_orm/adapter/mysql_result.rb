# typed: strict
# frozen_string_literal: true

require "mysql2"

module HakumiORM
  module Adapter
    class MysqlResult < Result
      extend T::Sig

      sig { params(rows: T::Array[T::Array[CellValue]], affected: Integer).void }
      def initialize(rows, affected)
        @rows = T.let(rows, T::Array[T::Array[CellValue]])
        @affected = T.let(affected, Integer)
      end

      sig { override.returns(Integer) }
      def row_count
        @rows.length
      end

      sig { override.params(row: Integer, col: Integer).returns(CellValue) }
      def get_value(row, col)
        @rows.dig(row, col)
      end

      sig { override.returns(T::Array[T::Array[CellValue]]) }
      def values
        @rows
      end

      sig { override.params(col: Integer).returns(T::Array[CellValue]) }
      def column_values(col)
        @rows.map { |r| r[col] }
      end

      sig { override.returns(Integer) }
      def affected_rows
        @affected
      end

      sig { override.void }
      def close; end
    end
  end
end
