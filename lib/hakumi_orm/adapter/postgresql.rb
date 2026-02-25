# typed: strict
# frozen_string_literal: true

require "pg"
require_relative "postgresql_result"

module HakumiORM
  module Adapter
    class Postgresql < Base
      extend T::Sig

      sig { override.returns(Dialect::Postgresql) }
      attr_reader :dialect

      sig { params(pg_conn: PG::Connection).void }
      def initialize(pg_conn)
        @pg_conn = T.let(pg_conn, PG::Connection)
        @dialect = T.let(Dialect::Postgresql.new, Dialect::Postgresql)
        @prepared = T.let({}, T::Hash[String, TrueClass])
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
        result = PostgresqlResult.new(@pg_conn.exec_params(sql, params))
        log_query_done(sql, params, start)
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
    end
  end
end
