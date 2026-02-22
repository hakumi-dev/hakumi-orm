# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
    class Result
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Integer) }
      def row_count; end

      sig { abstract.params(row: Integer, col: Integer).returns(T.nilable(String)) }
      def get_value(row, col); end

      sig { params(row: Integer, col: Integer).returns(String) }
      def fetch_value(row, col)
        val = get_value(row, col)
        raise "Unexpected NULL at row #{row}, col #{col}" if val.nil?

        val
      end

      sig { abstract.returns(T::Array[T::Array[T.nilable(String)]]) }
      def values; end

      sig { abstract.params(col: Integer).returns(T::Array[T.nilable(String)]) }
      def column_values(col); end

      sig { abstract.returns(Integer) }
      def affected_rows; end

      sig { abstract.void }
      def close; end
    end
  end
end
