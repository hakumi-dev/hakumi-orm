# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class SqliteSchemaReader
      extend T::Sig

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { returns(T::Hash[String, TableInfo]) }
      def read_tables
        tables = T.let({}, T::Hash[String, TableInfo])

        read_table_names(tables)
        tables.each_key { |name| read_table_info(name, tables) }
        read_foreign_keys(tables)

        tables
      end

      private

      sig { params(tables: T::Hash[String, TableInfo]).void }
      def read_table_names(tables)
        result = @adapter.exec("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        i = T.let(0, Integer)
        while i < result.row_count
          name = result.fetch_value(i, 0)
          tables[name] = TableInfo.new(name)
          i += 1
        end
        result.close
      end

      sig { params(table_name: String, tables: T::Hash[String, TableInfo]).void }
      def read_table_info(table_name, tables)
        tbl = tables[table_name]
        return unless tbl

        result = @adapter.exec("PRAGMA table_info(#{table_name})")
        i = T.let(0, Integer)
        while i < result.row_count
          col_name = result.fetch_value(i, 1)
          col_type = result.fetch_value(i, 2)
          notnull = result.fetch_value(i, 3)
          dflt = result.get_value(i, 4)&.to_s
          pk = result.fetch_value(i, 5)

          tbl.primary_key = col_name if pk == "1"
          normalized = normalize_type(col_type)
          tbl.columns << ColumnInfo.new(
            name: col_name,
            data_type: normalized,
            udt_name: normalized,
            nullable: notnull == "0",
            default: dflt,
            max_length: nil
          )
          i += 1
        end
        result.close

        read_unique_indexes(table_name, tbl)
      end

      sig { params(raw: String).returns(String) }
      def normalize_type(raw)
        raw.upcase.sub(/\(.*\)/, "").strip
      end

      sig { params(table_name: String, tbl: TableInfo).void }
      def read_unique_indexes(table_name, tbl)
        result = @adapter.exec("PRAGMA index_list(#{table_name})")
        i = T.let(0, Integer)
        while i < result.row_count
          idx_name = result.fetch_value(i, 1)
          unique = result.fetch_value(i, 2)
          read_index_columns(idx_name, tbl) if unique == "1"
          i += 1
        end
        result.close
      end

      sig { params(idx_name: String, tbl: TableInfo).void }
      def read_index_columns(idx_name, tbl)
        result = @adapter.exec("PRAGMA index_info(#{idx_name})")
        i = T.let(0, Integer)
        while i < result.row_count
          col_name = result.fetch_value(i, 2)
          tbl.unique_columns << col_name
          i += 1
        end
        result.close
      end

      sig { params(tables: T::Hash[String, TableInfo]).void }
      def read_foreign_keys(tables)
        tables.each_key do |table_name|
          tbl = tables[table_name]
          next unless tbl

          read_table_fks(table_name, tbl)
        end
      end

      sig { params(table_name: String, tbl: TableInfo).void }
      def read_table_fks(table_name, tbl)
        result = @adapter.exec("PRAGMA foreign_key_list(#{table_name})")
        i = T.let(0, Integer)
        while i < result.row_count
          tbl.foreign_keys << ForeignKeyInfo.new(
            column_name: result.fetch_value(i, 3),
            foreign_table: result.fetch_value(i, 2),
            foreign_column: result.fetch_value(i, 4)
          )
          i += 1
        end
        result.close
      end
    end
  end
end
