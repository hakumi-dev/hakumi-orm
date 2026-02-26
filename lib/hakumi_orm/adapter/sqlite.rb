# typed: strict
# frozen_string_literal: true

require "sqlite3"
require_relative "sqlite_result"

module HakumiORM
  module Adapter
    class Sqlite < Base
      extend T::Sig

      AUTO_READ_STMT_CACHE_MAX = 64
      sig { override.returns(Dialect::Sqlite) }
      attr_reader :dialect

      sig { params(database: SQLite3::Database).void }
      def initialize(database)
        @db = T.let(database, SQLite3::Database)
        @dialect = T.let(Dialect::Sqlite.new, Dialect::Sqlite)
        @prepared = T.let({}, T::Hash[String, SQLite3::Statement])
        @auto_read_prepared = T.let({}, T::Hash[String, SQLite3::Statement])
        @auto_read_order = T.let([], T::Array[String])
      end

      sig { params(path: String).returns(Sqlite) }
      def self.connect(path)
        db = SQLite3::Database.new(path)
        db.results_as_hash = false
        new(db)
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(SqliteResult) }
      def exec_params(sql, params)
        return exec(sql) if params.empty?

        start = log_query_start
        rows =
          if cacheable_read_sql?(sql)
            read_rows_via_cached_stmt(sql, params)
          else
            coerce_raw_rows(@db.execute(sql, params))
          end
        r = SqliteResult.new(rows, @db.changes)
        log_query_done(sql, params, start)
        r
      end

      sig { override.params(sql: String).returns(SqliteResult) }
      def exec(sql)
        start = log_query_start
        rows =
          if cacheable_read_sql?(sql)
            read_rows_via_cached_stmt(sql, [].freeze)
          else
            coerce_raw_rows(@db.execute(sql))
          end
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
        stmt.bind_params(params) unless params.empty?
        rows = coerce_raw_rows(stmt.to_a)
        r = SqliteResult.new(rows, @db.changes)
        log_query_done(name, params, start)
        r
      end

      sig { override.void }
      def close
        @prepared.each_value(&:close)
        @prepared.clear
        @auto_read_prepared.each_value(&:close)
        @auto_read_prepared.clear
        @auto_read_order.clear
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

      sig { params(stmt: SQLite3::Statement).returns(T::Array[T::Array[CellValue]]) }
      def collect_rows(stmt)
        rows = T.let([], T::Array[T::Array[CellValue]])
        while (row = stmt.step)
          rows << coerce_raw_row(row)
        end
        rows
      end

      sig { params(sql: String).returns(T::Boolean) }
      def cacheable_read_sql?(sql)
        stripped = sql.lstrip
        stripped.start_with?("SELECT", "WITH")
      end

      sig { params(sql: String, params: T::Array[PGValue]).returns(T::Array[T::Array[CellValue]]) }
      def read_rows_via_cached_stmt(sql, params)
        stmt = @auto_read_prepared[sql]
        unless stmt
          stmt = prepare_auto_read_stmt(sql)
          @auto_read_prepared[sql] = stmt
          @auto_read_order << sql
          evict_auto_read_stmt_if_needed!
        end

        stmt.reset!
        bind_stmt_params(stmt, params)
        raw_rows =
          if params.empty?
            fetch_stmt_rows_step(stmt)
          else
            fetch_stmt_rows(stmt)
          end

        coerce_or_reuse_rows(raw_rows)
      end

      sig { params(sql: String).returns(SQLite3::Statement) }
      def prepare_auto_read_stmt(sql)
        @db.prepare(sql)
      end

      sig { params(stmt: SQLite3::Statement, params: T::Array[PGValue]).void }
      def bind_stmt_params(stmt, params)
        return if params.empty?

        stmt.bind_params(params)
      end

      sig { params(stmt: SQLite3::Statement).returns(T::Array[T::Array[Object]]) }
      def fetch_stmt_rows(stmt)
        stmt.to_a
      end

      sig { params(stmt: SQLite3::Statement).returns(T::Array[T::Array[Object]]) }
      def fetch_stmt_rows_step(stmt)
        raw_rows = T.let([], T::Array[T::Array[Object]])
        while (row = stmt.step)
          raw_rows << row
        end
        raw_rows
      end

      sig { void }
      def evict_auto_read_stmt_if_needed!
        return if @auto_read_order.length <= AUTO_READ_STMT_CACHE_MAX

        evicted_sql = @auto_read_order.shift
        return unless evicted_sql

        stmt = @auto_read_prepared.delete(evicted_sql)
        stmt&.close
      end

      sig { params(value: Object).returns(CellValue) }
      def coerce_cell(value)
        case value
        when NilClass then nil
        when String, Integer, Float, TrueClass, FalseClass, Time, Date, BigDecimal then value
        else
          value.to_s
        end
      end

      sig { params(raw_rows: T::Array[T::Array[Object]]).returns(T::Array[T::Array[CellValue]]) }
      def coerce_raw_rows(raw_rows)
        rows = T.let(::Array.new(raw_rows.length), T::Array[T::Array[CellValue]])
        i = 0
        while i < raw_rows.length
          rows[i] = coerce_raw_row(raw_rows.fetch(i))
          i += 1
        end
        rows
      end

      sig { params(raw_rows: T::Array[T::Array[Object]]).returns(T::Array[T::Array[CellValue]]) }
      def coerce_or_reuse_rows(raw_rows)
        return T.cast(raw_rows, T::Array[T::Array[CellValue]]) if rows_already_cell_values?(raw_rows)

        coerce_raw_rows(raw_rows)
      end

      sig { params(raw_rows: T::Array[T::Array[Object]]).returns(T::Boolean) }
      def rows_already_cell_values?(raw_rows)
        i = 0
        while i < raw_rows.length
          row = raw_rows.fetch(i)
          j = 0
          while j < row.length
            value = row.fetch(j)
            case value
            when NilClass, String, Integer, Float, TrueClass, FalseClass, Time, Date, BigDecimal
              nil
            else
              return false
            end
            j += 1
          end
          i += 1
        end
        true
      end

      sig { params(raw_row: T::Array[Object]).returns(T::Array[CellValue]) }
      def coerce_raw_row(raw_row)
        row = T.let(::Array.new(raw_row.length), T::Array[CellValue])
        j = 0
        while j < raw_row.length
          value = raw_row.fetch(j)
          row[j] =
            case value
            when NilClass then nil
            when String, Integer, Float, TrueClass, FalseClass, Time, Date, BigDecimal then value
            else
              value.to_s
            end
          j += 1
        end
        row
      end
    end
  end
end
