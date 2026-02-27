# typed: strict
# frozen_string_literal: true

# Internal component for adapter/base.
module HakumiORM
  module Adapter
    # Internal class for HakumiORM.
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!
      PREDICATE_BIND_REGEX = T.let(
        /
          (
            (?:[A-Za-z_]\w*|"[^"]+"|`[^`]+`)
            (?:\.(?:[A-Za-z_]\w*|"[^"]+"|`[^`]+`))?
          )
          \s*(?:=|<>|!=|<|>|<=|>=|LIKE|ILIKE|IN)\s*\(?\s*(?:\$\d+|\?)
        /ix,
        Regexp
      )

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

      sig { overridable.params(name: String, sql: String, params: T::Array[PGValue]).returns(Result) }
      def prepare_exec(name, sql, params)
        prepare(name, sql)
        exec_prepared(name, params)
      end

      sig { overridable.returns(Integer) }
      def last_insert_id
        raise HakumiORM::Error, "#{self.class.name} does not support last_insert_id (use RETURNING instead)"
      end

      sig { overridable.returns(T.nilable(Integer)) }
      def max_bind_params
        nil
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

      sig { params(sql: String, params: T::Array[PGValue], start: T.nilable(Float), note: T.nilable(String)).void }
      def log_query_done(sql, params, start, note: nil)
        return unless start

        log = HakumiORM.config.logger
        return unless log

        note ||= "TRANSACTION" if transaction_control_sql?(sql)
        safe_params = filter_params_for_log(sql, params)
        elapsed = T.let(
          T.cast(((T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float) - start) * 1000).round(2), Float),
          Float
        )
        config = HakumiORM.config
        log.debug do
          if config.pretty_sql_logs
            SqlLogFormatter.format(
              elapsed_ms: elapsed,
              sql: sql,
              params: safe_params,
              note: note,
              colorize: config.colorize_sql_logs
            )
          else
            suffix = note ? " [#{note}]" : ""
            if safe_params.empty?
              "[HakumiORM] (#{elapsed}ms) #{sql}#{suffix}"
            else
              "[HakumiORM] (#{elapsed}ms) #{sql} #{safe_params.inspect}#{suffix}"
            end
          end
        end
      end

      sig { params(sql: String, params: T::Array[PGValue]).returns(T::Array[PGValue]) }
      def filter_params_for_log(sql, params)
        return params if params.empty?
        return params unless sensitive_bind_reference?(sql)

        T.let(Array.new(params.length, HakumiORM.config.log_filter_mask), T::Array[PGValue])
      end

      sig { params(sql: String).returns(T::Boolean) }
      def sensitive_bind_reference?(sql)
        patterns = HakumiORM.config.log_filter_parameters
        return false if patterns.empty?

        lowered = sql.downcase
        return false unless patterns.any? { |entry| !entry.empty? && lowered.include?(entry.downcase) }

        insert_columns = extract_insert_columns(sql)
        return true if insert_columns.any? { |col| sensitive_column?(col, patterns) }

        predicate_column_tokens(sql).any? { |col| sensitive_column?(col, patterns) }
      end

      sig { params(sql: String).returns(T::Boolean) }
      def transaction_control_sql?(sql)
        stripped = sql.lstrip.upcase
        stripped.start_with?("BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE SAVEPOINT")
      end

      sig { params(column: String, patterns: T::Array[String]).returns(T::Boolean) }
      def sensitive_column?(column, patterns)
        lowered = column.downcase
        patterns.any? { |entry| !entry.empty? && lowered.include?(entry.downcase) }
      end

      sig { params(sql: String).returns(T::Array[String]) }
      def extract_insert_columns(sql)
        match = /\A\s*INSERT\s+INTO\s+.+?\(([^)]+)\)\s+VALUES\b/im.match(sql)
        return [] unless match

        raw = T.must(match[1])
        raw.split(",").map { |token| normalize_identifier(token) }.reject(&:empty?)
      end

      sig { params(sql: String).returns(T::Array[String]) }
      def predicate_column_tokens(sql)
        tokens = T.let([], T::Array[String])
        sql.scan(PREDICATE_BIND_REGEX) do |match|
          token = T.cast(match, T::Array[String]).first
          next unless token

          normalized = normalize_identifier(token)
          tokens << normalized unless normalized.empty?
        end
        tokens
      end

      sig { params(raw: String).returns(String) }
      def normalize_identifier(raw)
        token = raw.strip
        parts = token.split(".")
        id = parts.last || token
        id.gsub(/\A["`]|["`]\z/, "")
      end

      sig { params(blk: T.proc.params(adapter: Base).void).void }
      def run_top_level_transaction(&blk)
        frames = T.let([], T.nilable(T::Array[TxFrame]))
        @tx_frames = frames
        push_tx_frame
        exec("BEGIN").close
        @txn_depth = 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK").close
        rescue StandardError
          nil
        end
        fire_callbacks(frames.flat_map { |f| f[:after_rollback] }) if frames
        raise
      else
        exec("COMMIT").close
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
        exec("SAVEPOINT #{sp}").close
        @txn_depth = depth + 1
        blk.call(self)
      rescue StandardError
        begin
          exec("ROLLBACK TO SAVEPOINT #{sp}").close
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
        exec("RELEASE SAVEPOINT #{sp}").close
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
