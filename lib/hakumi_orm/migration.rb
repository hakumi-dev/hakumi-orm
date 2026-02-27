# typed: strict
# frozen_string_literal: true

require_relative "migration/column_definition"
require_relative "migration/table_definition"
require_relative "migration/sql_generator"

require_relative "migration/file_generator"
require_relative "migration/schema_fingerprint"

# These collaborators compose "Migration::Runner", so load them before "runner.rb".
require_relative "migration/file_info"
require_relative "migration/loader"
require_relative "migration/lock"
require_relative "migration/version_store"
require_relative "migration/executor"
require_relative "migration/runner"

module HakumiORM
  class Migration
    extend T::Sig

    NameLike = T.type_alias { T.any(String, Symbol) }
    DefaultValue = T.type_alias { T.nilable(T.any(String, Integer, Float, T::Boolean)) }

    @registry = T.let({}, T::Hash[String, T.class_of(Migration)])

    class << self
      extend T::Sig

      sig { params(value: DefaultValue).returns(T.nilable(String)) }
      def coerce_default(value)
        case value
        when nil then nil
        when true then "true"
        when false then "false"
        when Integer, Float then value.to_s
        when String then "'#{value.gsub("'", "''")}'"
        end
      end

      sig { void }
      def disable_ddl_transaction!
        @ddl_transaction_disabled = T.let(true, T.nilable(T::Boolean))
      end

      sig { returns(T::Boolean) }
      def ddl_transaction_disabled?
        @ddl_transaction_disabled == true
      end

      sig { params(name: String).returns(T.nilable(T.class_of(Migration))) }
      def lookup(name)
        @registry[name]
      end

      sig { params(subclass: T::Class[Migration]).void }
      def inherited(subclass)
        super
        klass_name = subclass.name
        @registry[klass_name] = T.cast(subclass, T.class_of(Migration)) if klass_name
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

    sig { params(name: NameLike, id: T.any(Symbol, FalseClass), blk: T.nilable(T.proc.params(t: TableDefinition).void)).void }
    def create_table(name, id: :bigserial, &blk)
      table_def = TableDefinition.new(name.to_s, id: id)
      blk&.call(table_def)
      sqls = SqlGenerator.create_table_with_fks(table_def, dialect)
      sqls.each { |sql| adapter.exec(sql).close }
    end

    sig { params(name: NameLike).void }
    def drop_table(name)
      adapter.exec(SqlGenerator.drop_table(name.to_s, dialect)).close
    end

    sig { params(old_name: NameLike, new_name: NameLike).void }
    def rename_table(old_name, new_name)
      adapter.exec(SqlGenerator.rename_table(old_name.to_s, new_name.to_s, dialect)).close
    end

    sig { params(table: NameLike, col_name: NameLike, type: Symbol, null: T::Boolean, default: DefaultValue, limit: T.nilable(Integer), precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
    def add_column(table, col_name, type, null: true, default: nil, limit: nil, precision: nil, scale: nil)
      col = ColumnDefinition.new(
        name: col_name.to_s, type: type, null: null, default: Migration.coerce_default(default),
        limit: limit, precision: precision, scale: scale
      )
      adapter.exec(SqlGenerator.add_column(table.to_s, col, dialect)).close
    end

    sig { params(table: NameLike, col_name: NameLike).void }
    def remove_column(table, col_name)
      adapter.exec(SqlGenerator.remove_column(table.to_s, col_name.to_s, dialect)).close
    end

    sig { params(table: NameLike, col_name: NameLike, type: Symbol, null: T::Boolean, default: DefaultValue, precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
    def change_column(table, col_name, type, null: true, default: nil, precision: nil, scale: nil)
      col = ColumnDefinition.new(
        name: col_name.to_s, type: type, null: null, default: Migration.coerce_default(default),
        precision: precision, scale: scale
      )
      adapter.exec(SqlGenerator.change_column(table.to_s, col, dialect)).close
    end

    sig { params(table: NameLike, old_name: NameLike, new_name: NameLike).void }
    def rename_column(table, old_name, new_name)
      adapter.exec(SqlGenerator.rename_column(table.to_s, old_name.to_s, new_name.to_s, dialect)).close
    end

    sig { params(table: NameLike, columns: T::Array[NameLike], unique: T::Boolean, name: T.nilable(String)).void }
    def add_index(table, columns, unique: false, name: nil)
      adapter.exec(SqlGenerator.add_index(table.to_s, columns.map(&:to_s), dialect: dialect, unique: unique, name: name)).close
    end

    sig { params(table: NameLike, columns: T::Array[NameLike], name: T.nilable(String)).void }
    def remove_index(table, columns, name: nil)
      adapter.exec(SqlGenerator.remove_index(table.to_s, columns.map(&:to_s), dialect: dialect, name: name)).close
    end

    sig { params(from_table: NameLike, to_table: NameLike, column: NameLike, primary_key: String, on_delete: T.nilable(Symbol)).void }
    def add_foreign_key(from_table, to_table, column:, primary_key: "id", on_delete: nil)
      sql = SqlGenerator.add_foreign_key(
        from_table.to_s, to_table.to_s,
        column: column.to_s, dialect: dialect, primary_key: primary_key, on_delete: on_delete
      )
      adapter.exec(sql).close
    end

    sig { params(from_table: NameLike, to_table: NameLike, column: T.nilable(NameLike)).void }
    def remove_foreign_key(from_table, to_table, column: nil)
      adapter.exec(SqlGenerator.remove_foreign_key(from_table.to_s, to_table.to_s, dialect: dialect, column: column&.to_s)).close
    end

    sig { params(sql: String).void }
    def execute(sql)
      adapter.exec(sql).close
    end

    private

    sig { returns(Dialect::Base) }
    def dialect
      adapter.dialect
    end
  end
end
