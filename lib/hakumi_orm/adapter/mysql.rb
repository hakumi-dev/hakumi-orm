# typed: strict
# frozen_string_literal: true

require "mysql2"
require_relative "mysql_result"

module HakumiORM
  module Adapter
    class Mysql < Base
      extend T::Sig

      sig { override.returns(Dialect::Mysql) }
      attr_reader :dialect

      sig { params(client: Mysql2::Client).void }
      def initialize(client)
        @client = T.let(client, Mysql2::Client)
        @dialect = T.let(Dialect::Mysql.new, Dialect::Mysql)
        @prepared = T.let({}, T::Hash[String, Mysql2::Statement])
      end

      sig { params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Mysql) }
      def self.connect(params)
        client = Mysql2::Client.new(params.merge(cast: true, as: :array, database_timezone: :utc,
                                                 application_timezone: :utc))
        client.query("SET time_zone = '+00:00'")
        new(client)
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(MysqlResult) }
      def exec_params(sql, params)
        if params.empty?
          start = log_query_start
          result = @client.query(sql, as: :array, cast: true)
          rows = result_to_rows(result)
          r = MysqlResult.new(rows, safe_affected_rows)
          log_query_done(sql, params, start)
          return r
        end

        start = log_query_start
        stmt = @client.prepare(sql)
        # Sorbet cannot verify splats on dynamically-sized arrays (error 7019);
        # mysql2's C extension requires positional args for bind parameters.
        result = T.unsafe(stmt).execute(*mysql_params(params), as: :array)
        rows = result_to_rows(result)
        r = MysqlResult.new(rows, stmt.affected_rows)
        log_query_done(sql, params, start)
        r
      ensure
        stmt&.close
      end

      sig { override.params(sql: String).returns(MysqlResult) }
      def exec(sql)
        start = log_query_start
        result = @client.query(sql, as: :array, cast: true)
        rows = result_to_rows(result)
        r = MysqlResult.new(rows, safe_affected_rows)
        log_query_done(sql, [], start)
        r
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        return if @prepared.key?(name)

        @prepared[name] = @client.prepare(sql)
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(MysqlResult) }
      def exec_prepared(name, params)
        start = log_query_start
        stmt = @prepared[name]
        raise HakumiORM::Error, "Statement #{name.inspect} not prepared" unless stmt

        # Sorbet cannot verify splats on dynamically-sized arrays (error 7019);
        # mysql2's C extension requires positional args for bind parameters.
        result = T.unsafe(stmt).execute(*mysql_params(params), as: :array)
        rows = result_to_rows(result)
        r = MysqlResult.new(rows, stmt.affected_rows)
        log_query_done(name, params, start)
        r
      end

      sig { override.returns(Integer) }
      def last_insert_id
        @client.last_id
      end

      sig { override.returns(T::Boolean) }
      def alive?
        @client.ping
      rescue StandardError
        false
      end

      sig { override.void }
      def close
        @prepared.each_value(&:close)
        @prepared.clear
        @client.close
      end

      private

      sig { params(params: T::Array[PGValue]).returns(T::Array[PGValue]) }
      def mysql_params(params)
        params.map do |v|
          case v
          when "t" then 1
          when "f" then 0
          else v
          end
        end
      end

      # MySQL 9.x raises Mysql2::Error on affected_rows after SELECT queries
      sig { returns(Integer) }
      def safe_affected_rows
        @client.affected_rows
      rescue Mysql2::Error
        0
      end

      sig { params(result: T.nilable(Mysql2::Result)).returns(T::Array[T::Array[CellValue]]) }
      def result_to_rows(result)
        return [] unless result

        result.to_a
      end
    end
  end
end
