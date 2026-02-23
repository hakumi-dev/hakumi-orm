# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
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
        SELECT c.relname AS table_name, a.attname AS column_name
        FROM pg_index ix
        JOIN pg_class t ON t.oid = ix.indrelid
        JOIN pg_class c ON c.oid = ix.indrelid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE ix.indisunique AND NOT ix.indisprimary
          AND array_length(ix.indkey, 1) = 1
          AND n.nspname = $1
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

      PG_ENUM_VALUES_SQL = <<~SQL
        SELECT t.typname, e.enumlabel
        FROM pg_type t
        JOIN pg_enum e ON t.oid = e.enumtypid
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE n.nspname = $1
        ORDER BY t.typname, e.enumsortorder
      SQL

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { params(schema: String).returns(T::Hash[String, TableInfo]) }
      def read_tables(schema: "public")
        tables = T.let({}, T::Hash[String, TableInfo])

        enum_map = read_enum_values(schema)
        read_table_names(schema, tables)
        read_columns(schema, tables, enum_map)
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

      sig { params(schema: String).returns(T::Hash[String, T::Array[String]]) }
      def read_enum_values(schema)
        enum_map = T.let({}, T::Hash[String, T::Array[String]])
        result = @adapter.exec_params(PG_ENUM_VALUES_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          type_name = result.fetch_value(i, 0)
          label = result.fetch_value(i, 1)
          (enum_map[type_name] ||= []) << label
          i += 1
        end
        result.close
        enum_map
      end

      sig { params(schema: String, tables: T::Hash[String, TableInfo], enum_map: T::Hash[String, T::Array[String]]).void }
      def read_columns(schema, tables, enum_map)
        result = @adapter.exec_params(PG_COLUMNS_SQL, [schema])
        i = T.let(0, Integer)
        while i < result.row_count
          tbl = tables[result.fetch_value(i, 0)]
          if tbl
            max_len_raw = result.get_value(i, 6)
            udt = result.fetch_value(i, 3)
            tbl.columns << ColumnInfo.new(
              name: result.fetch_value(i, 1),
              data_type: result.fetch_value(i, 2),
              udt_name: udt,
              nullable: result.fetch_value(i, 4) == "YES",
              default: result.get_value(i, 5),
              max_length: max_len_raw&.to_i,
              enum_values: enum_map[udt]
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
