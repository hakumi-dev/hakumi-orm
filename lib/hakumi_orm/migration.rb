# typed: strict
# frozen_string_literal: true

require_relative "migration/column_definition"
require_relative "migration/table_definition"
require_relative "migration/sql_generator"
require_relative "migration/runner"
require_relative "migration/file_generator"
require_relative "migration/schema_fingerprint"

module HakumiORM
  class Migration
    extend T::Sig

    class << self
      extend T::Sig

      sig { void }
      def disable_ddl_transaction!
        @ddl_transaction_disabled = T.let(true, T.nilable(T::Boolean))
      end

      sig { returns(T::Boolean) }
      def ddl_transaction_disabled?
        @ddl_transaction_disabled == true
      end
    end

    sig { returns(Adapter::Base) }
    attr_reader :adapter

    sig { params(adapter: Adapter::Base).void }
    def initialize(adapter)
      @adapter = T.let(adapter, Adapter::Base)
    end

    sig { void }
    def up; end

    sig { void }
    def down; end

    sig { params(name: String, id: T.any(Symbol, FalseClass), blk: T.nilable(T.proc.params(t: TableDefinition).void)).void }
    def create_table(name, id: :bigserial, &blk)
      table_def = TableDefinition.new(name, id: id)
      blk&.call(table_def)
      sqls = SqlGenerator.create_table_with_fks(table_def, dialect)
      sqls.each { |sql| adapter.exec(sql) }
    end

    sig { params(name: String).void }
    def drop_table(name)
      adapter.exec(SqlGenerator.drop_table(name, dialect))
    end

    sig { params(old_name: String, new_name: String).void }
    def rename_table(old_name, new_name)
      adapter.exec(SqlGenerator.rename_table(old_name, new_name, dialect))
    end

    sig { params(table: String, col_name: String, type: Symbol, null: T::Boolean, default: T.nilable(String), limit: T.nilable(Integer), precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
    def add_column(table, col_name, type, null: true, default: nil, limit: nil, precision: nil, scale: nil)
      col = ColumnDefinition.new(
        name: col_name, type: type, null: null, default: default,
        limit: limit, precision: precision, scale: scale
      )
      adapter.exec(SqlGenerator.add_column(table, col, dialect))
    end

    sig { params(table: String, col_name: String).void }
    def remove_column(table, col_name)
      adapter.exec(SqlGenerator.remove_column(table, col_name, dialect))
    end

    sig { params(table: String, col_name: String, type: Symbol, null: T::Boolean, default: T.nilable(String), precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
    def change_column(table, col_name, type, null: true, default: nil, precision: nil, scale: nil)
      col = ColumnDefinition.new(
        name: col_name, type: type, null: null, default: default,
        precision: precision, scale: scale
      )
      adapter.exec(SqlGenerator.change_column(table, col, dialect))
    end

    sig { params(table: String, old_name: String, new_name: String).void }
    def rename_column(table, old_name, new_name)
      adapter.exec(SqlGenerator.rename_column(table, old_name, new_name, dialect))
    end

    sig { params(table: String, columns: T::Array[String], unique: T::Boolean, name: T.nilable(String)).void }
    def add_index(table, columns, unique: false, name: nil)
      adapter.exec(SqlGenerator.add_index(table, columns, dialect: dialect, unique: unique, name: name))
    end

    sig { params(table: String, columns: T::Array[String], name: T.nilable(String)).void }
    def remove_index(table, columns, name: nil)
      adapter.exec(SqlGenerator.remove_index(table, columns, dialect: dialect, name: name))
    end

    sig { params(from_table: String, to_table: String, column: String, primary_key: String, on_delete: T.nilable(Symbol)).void }
    def add_foreign_key(from_table, to_table, column:, primary_key: "id", on_delete: nil)
      sql = SqlGenerator.add_foreign_key(
        from_table, to_table,
        column: column, dialect: dialect, primary_key: primary_key, on_delete: on_delete
      )
      adapter.exec(sql)
    end

    sig { params(from_table: String, to_table: String, column: T.nilable(String)).void }
    def remove_foreign_key(from_table, to_table, column: nil)
      adapter.exec(SqlGenerator.remove_foreign_key(from_table, to_table, dialect: dialect, column: column))
    end

    sig { params(sql: String).void }
    def execute(sql)
      adapter.exec(sql)
    end

    private

    sig { returns(Dialect::Base) }
    def dialect
      adapter.dialect
    end
  end
end
