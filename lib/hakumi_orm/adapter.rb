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

    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Dialect::Base) }
      def dialect; end

      sig { abstract.params(sql: String, params: T::Array[PGValue]).returns(Result) }
      def exec_params(sql, params); end

      sig { abstract.params(sql: String).returns(Result) }
      def exec(sql); end

      sig { abstract.void }
      def close; end

      sig { params(blk: T.proc.params(adapter: Base).void).void }
      def transaction(&blk)
        exec("BEGIN")
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK")
        rescue StandardError
          nil
        end
        raise
      else
        exec("COMMIT")
      end
    end
  end
end
