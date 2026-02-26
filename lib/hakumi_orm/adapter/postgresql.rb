# typed: strict
# frozen_string_literal: true

require "pg"
require_relative "postgresql_result"

module HakumiORM
  module Adapter
    class Postgresql < Base
      extend T::Sig

      EXEC_PARAMS_STMT_CACHE_MAX = 64

      sig { override.returns(Dialect::Postgresql) }
      attr_reader :dialect

      sig { params(pg_conn: PG::Connection).void }
      def initialize(pg_conn)
        @pg_conn = T.let(pg_conn, PG::Connection)
        @dialect = T.let(Dialect::Postgresql.new, Dialect::Postgresql)
        @prepared = T.let({}, T::Hash[String, TrueClass])
        @exec_params_stmt_by_sql = T.let({}, T::Hash[String, String])
        @exec_params_stmt_order = T.let([], T::Array[String])
        @exec_params_stmt_seq = T.let(0, Integer)
      end

      sig { params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Postgresql) }
      def self.connect(params)
        conn = PG.connect(params)
        conn.exec("SET timezone = 'UTC'").clear
        new(conn)
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(PostgresqlResult) }
      def exec_params(sql, params)
        if params.empty?
          start = log_query_start
          result = PostgresqlResult.new(@pg_conn.exec(sql))
          log_query_done(sql, params, start)
          return result
        end

        start = log_query_start
        stmt_name, cache_hit = cached_exec_params_stmt_name(sql)
        result = PostgresqlResult.new(@pg_conn.exec_prepared(stmt_name, params))
        log_query_done(sql, params, start, note: cache_hit ? "PREPARED" : nil)
        result
      end

      sig { override.params(sql: String).returns(PostgresqlResult) }
      def exec(sql)
        start = log_query_start
        result = PostgresqlResult.new(@pg_conn.exec(sql))
        log_query_done(sql, [], start)
        result
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        return if @prepared.key?(name)

        @pg_conn.prepare(name, sql)
        @prepared[name] = true
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(PostgresqlResult) }
      def exec_prepared(name, params)
        start = log_query_start
        result = PostgresqlResult.new(@pg_conn.exec_prepared(name, params))
        log_query_done(name, params, start)
        result
      end

      sig { override.returns(T::Boolean) }
      def alive?
        @pg_conn.status == PG::Constants::CONNECTION_OK
      rescue StandardError
        false
      end

      sig { override.void }
      def close
        @pg_conn.close
      end

      private

      sig { params(sql: String).returns([String, T::Boolean]) }
      def cached_exec_params_stmt_name(sql)
        cached = @exec_params_stmt_by_sql[sql]
        return [cached, true] if cached

        evict_exec_params_stmt_if_needed

        @exec_params_stmt_seq += 1
        stmt_name = "hakumi_auto_#{@exec_params_stmt_seq}"
        @pg_conn.prepare(stmt_name, sql)
        @exec_params_stmt_by_sql[sql] = stmt_name
        @exec_params_stmt_order << sql
        [stmt_name, false]
      end

      sig { void }
      def evict_exec_params_stmt_if_needed
        return unless @exec_params_stmt_order.length >= EXEC_PARAMS_STMT_CACHE_MAX

        oldest_sql = @exec_params_stmt_order.shift
        return unless oldest_sql

        stmt_name = @exec_params_stmt_by_sql.delete(oldest_sql)
        return unless stmt_name

        @pg_conn.exec("DEALLOCATE #{stmt_name}").clear
      rescue PG::Error
        nil
      end
    end
  end
end
