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

      sig { abstract.params(name: String, sql: String).void }
      def prepare(name, sql); end

      sig { abstract.params(name: String, params: T::Array[PGValue]).returns(Result) }
      def exec_prepared(name, params); end

      sig { abstract.void }
      def close; end

      sig { params(requires_new: T::Boolean, blk: T.proc.params(adapter: Base).void).void }
      def transaction(requires_new: false, &blk)
        @txn_depth = T.let(@txn_depth, T.nilable(Integer))
        depth = @txn_depth || 0

        if depth.zero?
          run_top_level_transaction(&blk)
        elsif requires_new
          run_savepoint_transaction(depth, &blk)
        else
          blk.call(self)
        end
      end

      private

      sig { params(blk: T.proc.params(adapter: Base).void).void }
      def run_top_level_transaction(&blk)
        exec("BEGIN")
        @txn_depth = 1
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
      ensure
        @txn_depth = 0
      end

      sig { params(depth: Integer, blk: T.proc.params(adapter: Base).void).void }
      def run_savepoint_transaction(depth, &blk)
        sp = "hakumi_sp_#{depth}"
        exec("SAVEPOINT #{sp}")
        @txn_depth = depth + 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK TO SAVEPOINT #{sp}")
        rescue StandardError
          nil
        end
        raise
      else
        exec("RELEASE SAVEPOINT #{sp}")
      ensure
        @txn_depth = depth
      end
    end
  end
end
