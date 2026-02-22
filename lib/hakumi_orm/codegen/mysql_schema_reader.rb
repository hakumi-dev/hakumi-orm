# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class MysqlSchemaReader
      extend T::Sig

      TABLES_SQL = <<~SQL
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = ? AND table_type = 'BASE TABLE'
        ORDER BY table_name
      SQL

      COLUMNS_SQL = <<~SQL
        SELECT table_name, column_name, data_type, column_type,
               is_nullable, column_default, character_maximum_length
        FROM information_schema.columns
        WHERE table_schema = ?
        ORDER BY table_name, ordinal_position
      SQL

      PRIMARY_KEYS_SQL = <<~SQL
        SELECT table_name, column_name
        FROM information_schema.key_column_usage
        WHERE table_schema = ? AND constraint_name = 'PRIMARY'
      SQL

      UNIQUE_COLUMNS_SQL = <<~SQL
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
         AND tc.table_name = kcu.table_name
        WHERE tc.constraint_type = 'UNIQUE' AND tc.table_schema = ?
      SQL

      FOREIGN_KEYS_SQL = <<~SQL
        SELECT kcu.table_name, kcu.column_name,
               kcu.referenced_table_name, kcu.referenced_column_name
        FROM information_schema.key_column_usage kcu
        WHERE kcu.table_schema = ?
          AND kcu.referenced_table_name IS NOT NULL
      SQL

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { params(schema: String).returns(T::Hash[String, TableInfo]) }
      def read_tables(schema:)
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
        result = @adapter.exec_params(TABLES_SQL, [schema])
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
        result = @adapter.exec_params(COLUMNS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          if tbl
            data_type = result.fetch_value(i, 2)
            column_type = result.fetch_value(i, 3)
            resolved_type = column_type == "tinyint(1)" ? "tinyint(1)" : data_type
            max_len_raw = result.get_value(i, 6)
            tbl.columns << ColumnInfo.new(
              name: result.fetch_value(i, 1),
              data_type: resolved_type,
              udt_name: resolved_type,
              nullable: result.fetch_value(i, 4) == "YES",
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
        result = @adapter.exec_params(PRIMARY_KEYS_SQL, [schema])
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
        result = @adapter.exec_params(UNIQUE_COLUMNS_SQL, [schema])
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
        result = @adapter.exec_params(FOREIGN_KEYS_SQL, [schema])
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
