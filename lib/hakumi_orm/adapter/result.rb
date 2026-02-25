# typed: strict
# frozen_string_literal: true

require "bigdecimal"

module HakumiORM
  module Adapter
    # Database drivers with C-level casting (PG::TypeMapByColumn, mysql2 prepared
    # statements) return native Ruby types instead of strings. CellValue is the
    # union of all types a result cell can hold across all supported adapters.
    CellValue = T.type_alias { T.nilable(T.any(String, Integer, Float, T::Boolean, Time, Date, BigDecimal)) }

    class Result
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Integer) }
      def row_count; end

      sig { abstract.params(row: Integer, col: Integer).returns(CellValue) }
      def get_value(row, col); end

      # Convenience accessor that guarantees a non-nil String.
      # Used by schema readers and migration runners (cold path).
      sig { params(row: Integer, col: Integer).returns(String) }
      def fetch_value(row, col)
        val = get_value(row, col)
        raise "Unexpected NULL at row #{row}, col #{col}" if val.nil?

        val.to_s
      end

      sig { abstract.returns(T::Array[T::Array[CellValue]]) }
      def values; end

      # Adapters that support driver-level decoding (e.g. PG) can override this.
      # Default is a no-op so generated code can call it without adapter checks.
      sig { params(_type_map: Object).void }
      def apply_type_map!(_type_map); end

      sig { abstract.params(col: Integer).returns(T::Array[CellValue]) }
      def column_values(col); end

      sig { abstract.returns(Integer) }
      def affected_rows; end

      sig { abstract.void }
      def close; end
    end
  end
end
