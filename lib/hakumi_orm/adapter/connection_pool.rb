# typed: strict
# frozen_string_literal: true

# Internal component for adapter/connection_pool.
module HakumiORM
  module Adapter
    # Internal class for HakumiORM.
    class ConnectionPool < Base
      extend T::Sig

      sig { override.returns(Dialect::Base) }
      attr_reader :dialect

      sig do
        params(
          size: Integer,
          timeout: Float,
          connector: T.proc.returns(Base)
        ).void
      end
      def initialize(size: 5, timeout: 5.0, &connector)
        @size = T.let(size, Integer)
        @timeout = T.let(timeout, Float)
        @connector = T.let(connector, T.proc.returns(Base))
        @available = T.let([], T::Array[Base])
        @in_use = T.let({}, T::Hash[Integer, Base])
        @total = T.let(0, Integer)
        @waiting = T.let(0, Integer)
        @dead = T.let(0, Integer)
        @mutex = T.let(Mutex.new, Mutex)
        @cond = T.let(ConditionVariable.new, ConditionVariable)

        first = connector.call
        @dialect = T.let(first.dialect, Dialect::Base)
        @available << first
        @total = 1
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(Result) }
      def exec_params(sql, params)
        with_connection { |conn| conn.exec_params(sql, params) }
      end

      sig { override.params(sql: String).returns(Result) }
      def exec(sql)
        with_connection { |conn| conn.exec(sql) }
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        with_connection { |conn| conn.prepare(name, sql) }
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(Result) }
      def exec_prepared(name, params)
        with_connection { |conn| conn.exec_prepared(name, params) }
      end

      sig { override.params(name: String, sql: String, params: T::Array[PGValue]).returns(Result) }
      def prepare_exec(name, sql, params)
        with_connection do |conn|
          conn.prepare(name, sql)
          conn.exec_prepared(name, params)
        end
      end

      sig { override.params(requires_new: T::Boolean, blk: T.proc.params(adapter: Base).void).void }
      def transaction(requires_new: false, &blk)
        with_connection do |conn|
          conn.transaction(requires_new: requires_new, &blk)
        end
      end

      sig { override.params(blk: T.proc.void).void }
      def after_commit(&blk)
        checked_out_connection!.after_commit(&blk)
      end

      sig { override.params(blk: T.proc.void).void }
      def after_rollback(&blk)
        checked_out_connection!.after_rollback(&blk)
      end

      sig { override.void }
      def close
        @mutex.synchronize do
          @available.each(&:close)
          @available.clear
          @in_use.each_value(&:close)
          @in_use.clear
          @total = 0
          @waiting = 0
          @dead = 0
        end
      end

      sig { returns(Integer) }
      def pool_size
        @size
      end

      sig { returns(Integer) }
      def active_connections
        @mutex.synchronize { @in_use.size }
      end

      sig { returns(Integer) }
      def available_connections
        @mutex.synchronize { @available.size }
      end

      sig { returns(Integer) }
      def total_connections
        @mutex.synchronize { @total }
      end

      sig { returns(Integer) }
      def waiting_connections
        @mutex.synchronize { @waiting }
      end

      sig { returns(Integer) }
      def dead_connections
        @mutex.synchronize { @dead }
      end

      sig { override.returns(T.nilable(PoolStats)) }
      def pool_stats
        @mutex.synchronize do
          {
            size: @size,
            connections: @total,
            busy: @in_use.size,
            idle: @available.size,
            waiting: @waiting,
            dead: @dead
          }
        end
      end

      private

      sig { returns(Base) }
      def checked_out_connection!
        tid = Thread.current.object_id
        conn = @mutex.synchronize { @in_use[tid] }
        raise HakumiORM::Error, "after_commit/after_rollback can only be called inside a transaction" unless conn

        conn
      end

      sig do
        type_parameters(:R)
          .params(blk: T.proc.params(conn: Base).returns(T.type_parameter(:R)))
          .returns(T.type_parameter(:R))
      end
      def with_connection(&blk)
        tid = Thread.current.object_id

        existing = @mutex.synchronize { @in_use[tid] }
        return blk.call(existing) if existing

        conn = checkout(tid)
        blk.call(conn)
      rescue StandardError
        if conn && !conn.alive?
          discard(tid)
          conn = nil
        end
        raise
      ensure
        checkin(tid) if conn
      end

      sig { params(tid: Integer).returns(Base) }
      def checkout(tid)
        deadline = Time.now.to_f + @timeout

        @mutex.synchronize do
          loop do
            conn = @available.pop
            if conn
              @in_use[tid] = conn
              return conn
            end

            if @total < @size
              conn = @connector.call
              @total += 1
              @dead -= 1 if @dead.positive?
              @in_use[tid] = conn
              return conn
            end

            remaining = deadline - Time.now.to_f
            raise TimeoutError, "Could not obtain a connection within #{@timeout}s" if remaining <= 0

            @waiting += 1
            begin
              @cond.wait(@mutex, remaining)
            ensure
              @waiting -= 1 if @waiting.positive?
            end
          end
        end
      end

      sig { params(tid: Integer).void }
      def checkin(tid)
        @mutex.synchronize do
          conn = @in_use.delete(tid)
          if conn
            @available << conn
            @cond.signal
          end
        end
      end

      sig { params(tid: Integer).void }
      def discard(tid)
        @mutex.synchronize do
          dead = @in_use.delete(tid)
          if dead
            begin
              dead.close
            rescue StandardError
              nil
            end
            @dead += 1
            @total -= 1
            @cond.signal
          end
        end
      end
    end
  end
end
