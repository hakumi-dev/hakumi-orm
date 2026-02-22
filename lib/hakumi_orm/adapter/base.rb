# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
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

      sig { params(blk: T.proc.void).void }
      def after_commit(&blk)
        @after_commit_callbacks = T.let(@after_commit_callbacks, T.nilable(T::Array[T.proc.void]))
        (@after_commit_callbacks ||= []) << blk
      end

      sig { params(blk: T.proc.void).void }
      def after_rollback(&blk)
        @after_rollback_callbacks = T.let(@after_rollback_callbacks, T.nilable(T::Array[T.proc.void]))
        (@after_rollback_callbacks ||= []) << blk
      end

      private

      sig { returns(T.nilable(Float)) }
      def log_query_start
        return nil unless HakumiORM.config.logger

        T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      end

      sig { params(sql: String, params: T::Array[PGValue], start: T.nilable(Float)).void }
      def log_query_done(sql, params, start)
        return unless start

        logger = HakumiORM.config.logger
        return unless logger

        elapsed = ((T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float) - start) * 1000).round(2)
        logger.debug { params.empty? ? "[HakumiORM] (#{elapsed}ms) #{sql}" : "[HakumiORM] (#{elapsed}ms) #{sql} #{params.inspect}" }
      end

      sig { params(blk: T.proc.params(adapter: Base).void).void }
      def run_top_level_transaction(&blk)
        @after_commit_callbacks = T.let(nil, T.nilable(T::Array[T.proc.void]))
        @after_rollback_callbacks = T.let(nil, T.nilable(T::Array[T.proc.void]))
        @after_commit_callbacks = []
        @after_rollback_callbacks = []
        exec("BEGIN")
        @txn_depth = 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK")
        rescue StandardError
          nil
        end
        fire_callbacks(@after_rollback_callbacks)
        raise
      else
        exec("COMMIT")
        fire_callbacks(@after_commit_callbacks)
      ensure
        @txn_depth = 0
        @after_commit_callbacks = nil
        @after_rollback_callbacks = nil
      end

      sig { params(callbacks: T.nilable(T::Array[T.proc.void])).void }
      def fire_callbacks(callbacks)
        return unless callbacks

        callbacks.each(&:call)
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
