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

      sig { params(bind: Bind).returns(PGValue) }
      def encode(bind)
        dialect.encode_bind(bind)
      end

      sig { overridable.returns(T::Boolean) }
      def alive?
        true
      end

      sig { overridable.returns(Integer) }
      def last_insert_id
        raise HakumiORM::Error, "#{self.class.name} does not support last_insert_id (use RETURNING instead)"
      end

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
        current_tx_frame[:after_commit] << blk
      end

      sig { params(blk: T.proc.void).void }
      def after_rollback(&blk)
        current_tx_frame[:after_rollback] << blk
      end

      CallbackList = T.type_alias { T::Array[T.proc.void] }
      TxFrame = T.type_alias { { after_commit: CallbackList, after_rollback: CallbackList } }

      private

      sig { returns(TxFrame) }
      def current_tx_frame
        @tx_frames = T.let(@tx_frames, T.nilable(T::Array[TxFrame]))
        frames = @tx_frames
        raise HakumiORM::Error, "after_commit/after_rollback can only be called inside a transaction" unless frames && !frames.empty?

        frames.fetch(-1)
      end

      sig { returns(TxFrame) }
      def push_tx_frame
        @tx_frames = T.let(@tx_frames, T.nilable(T::Array[TxFrame]))
        @tx_frames ||= []
        frame = { after_commit: T.let([], CallbackList), after_rollback: T.let([], CallbackList) }
        @tx_frames << frame
        frame
      end

      sig { returns(T.nilable(Float)) }
      def log_query_start
        return nil unless HakumiORM.config.logger

        T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
      end

      sig { params(sql: String, params: T::Array[PGValue], start: T.nilable(Float)).void }
      def log_query_done(sql, params, start)
        return unless start

        log = HakumiORM.config.logger
        return unless log

        elapsed = ((T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float) - start) * 1000).round(2)
        log.debug { params.empty? ? "[HakumiORM] (#{elapsed}ms) #{sql}" : "[HakumiORM] (#{elapsed}ms) #{sql} #{params.inspect}" }
      end

      sig { params(blk: T.proc.params(adapter: Base).void).void }
      def run_top_level_transaction(&blk)
        frames = T.let([], T.nilable(T::Array[TxFrame]))
        @tx_frames = frames
        push_tx_frame
        exec("BEGIN")
        @txn_depth = 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK")
        rescue StandardError
          nil
        end
        fire_callbacks(frames.flat_map { |f| f[:after_rollback] }) if frames
        raise
      else
        exec("COMMIT")
        fire_callbacks(frames.flat_map { |f| f[:after_commit] }) if frames
      ensure
        @txn_depth = 0
        @tx_frames = nil
      end

      sig { params(callbacks: T::Array[T.proc.void]).void }
      def fire_callbacks(callbacks)
        first_error = T.let(nil, T.nilable(StandardError))
        callbacks.each do |cb|
          cb.call
        rescue StandardError => e
          first_error ||= e
        end
        raise first_error if first_error
      end

      sig { params(depth: Integer, blk: T.proc.params(adapter: Base).void).void }
      def run_savepoint_transaction(depth, &blk)
        sp = "hakumi_sp_#{depth}"
        push_tx_frame
        exec("SAVEPOINT #{sp}")
        @txn_depth = depth + 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK TO SAVEPOINT #{sp}")
        rescue StandardError
          nil
        end
        frames = @tx_frames
        if frames
          frame = frames.pop
          fire_callbacks(frame[:after_rollback]) if frame
        end
        raise
      else
        exec("RELEASE SAVEPOINT #{sp}")
        frames = @tx_frames
        if frames
          frame = frames.pop
          if frame
            parent = frames.last
            if parent
              parent[:after_commit].concat(frame[:after_commit])
              parent[:after_rollback].concat(frame[:after_rollback])
            end
          end
        end
      ensure
        @txn_depth = depth
      end
    end
  end
end
