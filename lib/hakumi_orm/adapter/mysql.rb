# typed: strict
# frozen_string_literal: true

require "mysql2"

module HakumiORM
  module Adapter
    class MysqlResult < Result
      extend T::Sig

      sig { params(rows: T::Array[T::Array[T.nilable(String)]], affected: Integer).void }
      def initialize(rows, affected)
        @rows = T.let(rows, T::Array[T::Array[T.nilable(String)]])
        @affected = T.let(affected, Integer)
      end

      sig { override.returns(Integer) }
      def row_count
        @rows.length
      end

      sig { override.params(row: Integer, col: Integer).returns(T.nilable(String)) }
      def get_value(row, col)
        @rows.dig(row, col)
      end

      sig { override.returns(T::Array[T::Array[T.nilable(String)]]) }
      def values
        @rows
      end

      sig { override.params(col: Integer).returns(T::Array[T.nilable(String)]) }
      def column_values(col)
        @rows.map { |r| r[col] }
      end

      sig { override.returns(Integer) }
      def affected_rows
        @affected
      end

      sig { override.void }
      def close; end
    end

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
        new(Mysql2::Client.new(params.merge(cast: false, as: :array)))
      end

      sig { override.params(sql: String, params: T::Array[PGValue]).returns(MysqlResult) }
      def exec_params(sql, params)
        stmt = @client.prepare(sql)
        result = T.unsafe(stmt).execute(*params, as: :array, cast: false)
        rows = result_to_rows(result)
        MysqlResult.new(rows, @client.affected_rows)
      ensure
        stmt&.close
      end

      sig { override.params(sql: String).returns(MysqlResult) }
      def exec(sql)
        result = @client.query(sql, as: :array, cast: false)
        rows = result_to_rows(result)
        MysqlResult.new(rows, @client.affected_rows)
      end

      sig { override.params(name: String, sql: String).void }
      def prepare(name, sql)
        return if @prepared.key?(name)

        @prepared[name] = @client.prepare(sql)
      end

      sig { override.params(name: String, params: T::Array[PGValue]).returns(MysqlResult) }
      def exec_prepared(name, params)
        stmt = @prepared[name]
        raise HakumiORM::Error, "Statement #{name.inspect} not prepared" unless stmt

        result = T.unsafe(stmt).execute(*params, as: :array, cast: false)
        rows = result_to_rows(result)
        MysqlResult.new(rows, @client.affected_rows)
      end

      sig { override.void }
      def close
        @prepared.each_value(&:close)
        @prepared.clear
        @client.close
      end

      private

      sig { params(result: T.nilable(Mysql2::Result)).returns(T::Array[T::Array[T.nilable(String)]]) }
      def result_to_rows(result)
        return [] unless result

        result.map do |row|
          row.map { |v| v&.to_s }
        end
      end
    end
  end
end
