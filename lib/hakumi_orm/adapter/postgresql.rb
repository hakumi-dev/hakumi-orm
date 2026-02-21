# typed: strict
# frozen_string_literal: true

require "pg"

module HakumiORM
  module Adapter
    class PostgresqlResult < Result
      extend T::Sig

      sig { params(pg_result: PG::Result).void }
      def initialize(pg_result)
        @pg_result = T.let(pg_result, PG::Result)
      end

      sig { override.returns(Integer) }
      def row_count
        @pg_result.ntuples
      end

      sig { override.params(row: Integer, col: Integer).returns(T.nilable(String)) }
      def get_value(row, col)
        @pg_result.getvalue(row, col)
      end

      sig { override.returns(T::Array[T::Array[T.nilable(String)]]) }
      def values
        @pg_result.values
      end

      sig { override.params(col: Integer).returns(T::Array[T.nilable(String)]) }
      def column_values(col)
        @pg_result.column_values(col)
      end

      sig { override.returns(Integer) }
      def affected_rows
        @pg_result.cmd_tuples
      end

      sig { override.void }
      def close
        @pg_result.clear
      end
    end

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
        new(PG.connect(params))
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(PostgresqlResult) }
      def exec_params(sql, params)
        PostgresqlResult.new(@pg_conn.exec_params(sql, params))
      end

      sig { override.params(sql: String).returns(PostgresqlResult) }
      def exec(sql)
        PostgresqlResult.new(@pg_conn.exec(sql))
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        return if @prepared.key?(name)

        @pg_conn.prepare(name, sql)
        @prepared[name] = true
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(PostgresqlResult) }
      def exec_prepared(name, params)
        PostgresqlResult.new(@pg_conn.exec_prepared(name, params))
      end

      sig { override.void }
      def close
        @pg_conn.close
      end
    end
  end
end
