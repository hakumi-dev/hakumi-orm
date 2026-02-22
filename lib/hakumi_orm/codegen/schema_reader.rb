# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class ColumnInfo < T::Struct
      const :name, String
      const :data_type, String
      const :udt_name, String
      const :nullable, T::Boolean
      const :default, T.nilable(String)
      const :max_length, T.nilable(Integer)
    end

    class ForeignKeyInfo < T::Struct
      const :column_name, String
      const :foreign_table, String
      const :foreign_column, String
    end

    class TableInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(T::Array[ColumnInfo]) }
      attr_reader :columns

      sig { returns(T::Array[ForeignKeyInfo]) }
      attr_reader :foreign_keys

      sig { returns(T::Array[String]) }
      attr_reader :unique_columns

      sig { returns(T.nilable(String)) }
      attr_accessor :primary_key

      sig { params(name: String).void }
      def initialize(name)
        @name = T.let(name, String)
        @columns = T.let([], T::Array[ColumnInfo])
        @foreign_keys = T.let([], T::Array[ForeignKeyInfo])
        @unique_columns = T.let([], T::Array[String])
        @primary_key = T.let(nil, T.nilable(String))
      end
    end

    class SchemaReader
      extend T::Sig

      PG_TABLES_SQL = <<~SQL
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = $1 AND table_type = 'BASE TABLE'
        ORDER BY table_name
      SQL

      PG_COLUMNS_SQL = <<~SQL
        SELECT table_name, column_name, data_type, udt_name,
               is_nullable, column_default, character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = $1
        ORDER BY table_name, ordinal_position
      SQL

      PG_PRIMARY_KEYS_SQL = <<~SQL
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = $1
      SQL

      PG_UNIQUE_COLUMNS_SQL = <<~SQL
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        WHERE tc.constraint_type = 'UNIQUE' AND tc.table_schema = $1
      SQL

      PG_FOREIGN_KEYS_SQL = <<~SQL
        SELECT tc.table_name, kcu.column_name,
               ccu.table_name AS foreign_table_name,
               ccu.column_name AS foreign_column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1
      SQL

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { params(schema: String).returns(T::Hash[String, TableInfo]) }
      def read_tables(schema: "public")
        tables = T.let({}, T::Hash[String, TableInfo])

        read_table_names(schema, tables)
        read_columns(schema, tables)
        read_primary_keys(schema, tables)
        read_unique_columns(schema, tables)
        read_foreign_keys(schema, tables)

        tables
      end

      private

      sig { params(schema: String, tables: T::Hash[String, TableInfo]).void }
      def read_table_names(schema, tables)
        result = @adapter.exec_params(PG_TABLES_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          name = result.fetch_value(i, 0)
          tables[name] = TableInfo.new(name)
          i += 1
        end
        result.close
      end

      sig { params(schema: String, tables: T::Hash[String, TableInfo]).void }
      def read_columns(schema, tables)
        result = @adapter.exec_params(PG_COLUMNS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          if tbl
            max_len_raw = result.get_value(i, 6)
            tbl.columns << ColumnInfo.new(
              name: result.fetch_value(i, 1),
              data_type: result.fetch_value(i, 2),
              udt_name: result.fetch_value(i, 3),
              nullable: result.fetch_value(i, 4) == "YES", # information_schema returns 'YES'/'NO', not boolean
              default: result.get_value(i, 5),
              max_length: max_len_raw&.to_i
            )
          end
          i += 1
        end
        result.close
      end

      sig { params(schema: String, tables: T::Hash[String, TableInfo]).void }
      def read_primary_keys(schema, tables)
        result = @adapter.exec_params(PG_PRIMARY_KEYS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          tbl.primary_key = result.fetch_value(i, 1) if tbl
          i += 1
        end
        result.close
      end

      sig { params(schema: String, tables: T::Hash[String, TableInfo]).void }
      def read_unique_columns(schema, tables)
        result = @adapter.exec_params(PG_UNIQUE_COLUMNS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          tbl.unique_columns << result.fetch_value(i, 1) if tbl
          i += 1
        end
        result.close
      end

      sig { params(schema: String, tables: T::Hash[String, TableInfo]).void }
      def read_foreign_keys(schema, tables)
        result = @adapter.exec_params(PG_FOREIGN_KEYS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          if tbl
            tbl.foreign_keys << ForeignKeyInfo.new(
              column_name: result.fetch_value(i, 1),
              foreign_table: result.fetch_value(i, 2),
              foreign_column: result.fetch_value(i, 3)
            )
          end
          i += 1
        end
        result.close
      end
    end
  end
end
