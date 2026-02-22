# typed: strict
# frozen_string_literal: true

require "sqlite3"
require_relative "sqlite_result"

module HakumiORM
  module Adapter
    class Sqlite < Base
      extend T::Sig

      sig { override.returns(Dialect::Sqlite) }
      attr_reader :dialect

      sig { params(database: SQLite3::Database).void }
      def initialize(database)
        @db = T.let(database, SQLite3::Database)
        @dialect = T.let(Dialect::Sqlite.new, Dialect::Sqlite)
        @prepared = T.let({}, T::Hash[String, SQLite3::Statement])
      end

      sig { params(path: String).returns(Sqlite) }
      def self.connect(path)
        db = SQLite3::Database.new(path)
        db.results_as_hash = false
        new(db)
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(SqliteResult) }
      def exec_params(sql, params)
        start = log_query_start
        stmt = @db.prepare(sql)
        bind_each(stmt, params)
        rows = collect_rows(stmt)
        r = SqliteResult.new(rows, @db.changes)
        log_query_done(sql, params, start)
        r
      ensure
        stmt&.close
      end

      sig { override.params(sql: String).returns(SqliteResult) }
      def exec(sql)
        start = log_query_start
        rows = @db.execute(sql).map { |r| r.map { |v| v&.to_s } }
        r = SqliteResult.new(rows, @db.changes)
        log_query_done(sql, [], start)
        r
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        return if @prepared.key?(name)

        @prepared[name] = @db.prepare(sql)
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(SqliteResult) }
      def exec_prepared(name, params)
        start = log_query_start
        stmt = @prepared[name]
        raise HakumiORM::Error, "Statement #{name.inspect} not prepared" unless stmt

        stmt.reset!
        bind_each(stmt, params)
        rows = collect_rows(stmt)
        r = SqliteResult.new(rows, @db.changes)
        log_query_done(name, params, start)
        r
      end

      sig { override.void }
      def close
        @prepared.each_value(&:close)
        @prepared.clear
        @db.close
      end

      private

      sig { params(stmt: SQLite3::Statement, params: T::Array[PGValue]).void }
      def bind_each(stmt, params)
        i = T.let(0, Integer)
        while i < params.length
          stmt.bind_param(i + 1, params[i])
          i += 1
        end
      end

      sig { params(stmt: SQLite3::Statement).returns(T::Array[T::Array[T.nilable(String)]]) }
      def collect_rows(stmt)
        rows = T.let([], T::Array[T::Array[T.nilable(String)]])
        while (row = stmt.step)
          rows << row.map { |v| v&.to_s }
        end
        rows
      end
    end
  end
end
