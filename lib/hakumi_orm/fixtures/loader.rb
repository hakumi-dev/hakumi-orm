# typed: strict
# frozen_string_literal: true

require "erb"
require "yaml"
require "date"
require "bigdecimal"
require "json"
require "zlib"
require_relative "reference_resolver"
module HakumiORM
  module Fixtures
    # Loads YAML fixtures into the configured database.
    class Loader
      extend T::Sig
      extend T::Helpers

      FixtureScalar = T.type_alias do
        T.nilable(T.any(String, Integer, Float, BigDecimal, Date, Time, T::Boolean, Symbol))
      end

      FixtureValue = T.type_alias do
        T.any(
          FixtureScalar,
          T::Array[FixtureScalar],
          T::Hash[String, FixtureScalar],
          T::Hash[Symbol, FixtureScalar]
        )
      end
      FixtureRow = T.type_alias { T::Hash[String, FixtureValue] }
      FixtureRowSet = T.type_alias { T::Hash[String, FixtureRow] }
      LoadedFixtures = T.type_alias { T::Hash[String, FixtureRowSet] }

      sig do
        params(
          adapter: Adapter::Base,
          tables: T::Hash[String, Codegen::TableInfo],
          verify_foreign_keys: T::Boolean
        ).void
      end
      def initialize(adapter:, tables:, verify_foreign_keys: false)
        @adapter = T.let(adapter, Adapter::Base)
        @tables = T.let(tables, T::Hash[String, Codegen::TableInfo])
        @resolver = T.let(ReferenceResolver.new(tables: @tables), ReferenceResolver)
        @verify_foreign_keys = T.let(verify_foreign_keys, T::Boolean)
      end

      sig do
        params(
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String])
        ).returns(Integer)
      end
      def load!(base_path:, fixtures_dir: nil, only_names: nil)
        rows_by_table = collect_fixture_rows(base_path: base_path, fixtures_dir: fixtures_dir, only_names: only_names)
        insert_fixture_tables!(rows_by_table)
        rows_by_table.keys.size
      end

      sig do
        params(
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String])
        ).returns(LoadedFixtures)
      end
      def load_with_data!(base_path:, fixtures_dir: nil, only_names: nil)
        rows_by_table = collect_fixture_rows(base_path: base_path, fixtures_dir: fixtures_dir, only_names: only_names)
        insert_fixture_tables!(rows_by_table)
        rows_by_table
      end

      private

      sig do
        params(
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String])
        ).returns(LoadedFixtures)
      end
      def collect_fixture_rows(base_path:, fixtures_dir:, only_names:)
        files = fixture_files(base_path: base_path, fixtures_dir: fixtures_dir, only_names: only_names)
        rows_by_table = T.let({}, LoadedFixtures)
        files.each do |file|
          table_name = table_name_for_file(base_path, file, fixtures_dir: fixtures_dir)
          table = @tables[table_name]
          next unless table

          labeled_rows = parse_labeled_rows(file)
          rows_by_table[table_name] = parse_labeled_rows_for_table(table, labeled_rows)
        end
        rows_by_table
      end

      sig do
        params(
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String])
        ).returns(T::Array[String])
      end
      def fixture_files(base_path:, fixtures_dir:, only_names:)
        root = fixtures_root(base_path: base_path, fixtures_dir: fixtures_dir)
        return [] unless Dir.exist?(root)

        if only_names && !only_names.empty?
          only_names.filter_map do |name|
            abs = File.expand_path("#{name}.yml", root)
            File.file?(abs) ? abs : nil
          end
        else
          Dir.glob(File.join(root, "**", "*.yml"))
             .reject { |f| f.start_with?(File.join(root, "files")) }
             .sort
        end
      end

      sig { params(base_path: String, fixtures_dir: T.nilable(String)).returns(String) }
      def fixtures_root(base_path:, fixtures_dir:)
        return File.expand_path(base_path, Dir.pwd) unless fixtures_dir

        File.expand_path(fixtures_dir, File.expand_path(base_path, Dir.pwd))
      end

      sig { params(base_path: String, file: String, fixtures_dir: T.nilable(String)).returns(String) }
      def table_name_for_file(base_path, file, fixtures_dir:)
        root = fixtures_root(base_path: base_path, fixtures_dir: fixtures_dir)
        relative = file.delete_prefix("#{root}/").delete_suffix(".yml")
        relative.tr("/", "_")
      end

      sig { params(path: String).returns(FixtureRowSet) }
      def parse_labeled_rows(path)
        src = File.read(path)
        rendered = ERB.new(src).result
        parsed = YAML.safe_load(
          rendered,
          permitted_classes: [Date, Time, BigDecimal, Symbol],
          aliases: true
        )
        return {} unless parsed.is_a?(Hash)

        rows = T.let({}, FixtureRowSet)
        parsed.each do |label, attrs|
          next unless label.is_a?(String) || label.is_a?(Symbol)
          next if label.to_s.start_with?("_")
          next unless attrs.is_a?(Hash)

          rows[label.to_s] = normalize_row(attrs)
        end
        rows
      end

      sig { params(table: Codegen::TableInfo, labeled_rows: FixtureRowSet).returns(FixtureRowSet) }
      def parse_labeled_rows_for_table(table, labeled_rows)
        rows = T.let({}, FixtureRowSet)
        labeled_rows.each do |label, row|
          rows[label] = apply_primary_key_defaults(table, label, row)
        end
        rows
      end

      sig { params(attrs: T::Hash[T.any(String, Symbol), FixtureValue]).returns(FixtureRow) }
      def normalize_row(attrs)
        row = T.let({}, FixtureRow)
        attrs.each { |k, v| row[k.to_s] = v }
        row
      end

      sig { params(table: Codegen::TableInfo, label: String, row: FixtureRow).returns(FixtureRow) }
      def apply_primary_key_defaults(table, label, row)
        pk = table.primary_key
        return row unless pk
        return row if row.key?(pk)

        column = table.columns.find { |c| c.name == pk }
        return row unless column

        if integer_column?(column)
          row.merge(pk => fixture_id(label))
        else
          row
        end
      end

      sig { params(rows_by_table: LoadedFixtures).void }
      def insert_fixture_tables!(rows_by_table)
        @resolver.insertion_order(rows_by_table.keys).each do |table_name|
          table = @tables[table_name]
          next unless table

          labeled_rows = rows_by_table[table_name] || {}
          rows = labeled_rows.flat_map do |label, row|
            @resolver.expand_row_fk_references(
              table: table,
              fixture_label: label,
              row: row,
              rows_by_table: rows_by_table
            )
          end
          replace_table_rows!(table, rows)
        end
        verify_foreign_keys!(rows_by_table.keys) if @verify_foreign_keys
      end

      sig { params(table_names: T::Array[String]).void }
      def verify_foreign_keys!(table_names)
        table_names.each do |table_name|
          table = @tables[table_name]
          next unless table

          table.foreign_keys.each do |fk|
            next unless table_names.include?(fk.foreign_table)

            orphans = orphan_count(table, fk)
            next if orphans.zero?

            raise HakumiORM::Error,
                  "Fixture foreign key check failed: #{table.name}.#{fk.column_name} -> " \
                  "#{fk.foreign_table}.#{fk.foreign_column} (#{orphans} orphan row(s))"
          end
        end
      end

      sig { params(table: Codegen::TableInfo, fk: Codegen::ForeignKeyInfo).returns(Integer) }
      def orphan_count(table, fk)
        child = @adapter.dialect.quote_id(table.name)
        parent = @adapter.dialect.quote_id(fk.foreign_table)
        child_col = @adapter.dialect.quote_id(fk.column_name)
        parent_col = @adapter.dialect.quote_id(fk.foreign_column)
        sql = <<~SQL.strip
          SELECT COUNT(*)
          FROM #{child} c
          LEFT JOIN #{parent} p ON c.#{child_col} = p.#{parent_col}
          WHERE c.#{child_col} IS NOT NULL AND p.#{parent_col} IS NULL
        SQL
        result = @adapter.exec(sql)
        count_value = result.get_value(0, 0)
        case count_value
        when Integer then count_value
        when String then count_value.to_i
        else 0
        end
      ensure
        result&.close
      end

      sig { params(column: Codegen::ColumnInfo).returns(T::Boolean) }
      def integer_column?(column)
        %w[smallint integer bigint int tinyint].include?(column.data_type.downcase)
      end

      sig { params(label: String).returns(Integer) }
      def fixture_id(label)
        id = Zlib.crc32(label) % 2_147_483_647
        id.zero? ? 1 : id
      end

      sig { params(table: Codegen::TableInfo, rows: T::Array[FixtureRow]).void }
      def replace_table_rows!(table, rows)
        delete_all_sql = "DELETE FROM #{@adapter.dialect.quote_id(table.name)}"
        @adapter.exec(delete_all_sql).close
        return if rows.empty?

        rows.each { |row| insert_row!(table, row) }
      end

      sig { params(table: Codegen::TableInfo, row: FixtureRow).void }
      def insert_row!(table, row)
        columns, values = row_columns_and_values(table, row)

        return if columns.empty?

        markers = bind_markers(values.length)
        sql = "INSERT INTO #{@adapter.dialect.quote_id(table.name)} (#{columns.join(", ")}) VALUES (#{markers.join(", ")})"
        @adapter.exec_params(sql, values).close
      end

      sig { params(table: Codegen::TableInfo, row: FixtureRow).returns([T::Array[String], T::Array[PGValue]]) }
      def row_columns_and_values(table, row)
        columns = T.let([], T::Array[String])
        values = T.let([], T::Array[PGValue])
        table.columns.each do |column|
          next unless row.key?(column.name)

          columns << @adapter.dialect.quote_id(column.name)
          values << encode_value(column, row[column.name])
        end
        [columns, values]
      end

      sig { params(length: Integer).returns(T::Array[String]) }
      def bind_markers(length)
        markers = T.let([], T::Array[String])
        i = T.let(0, Integer)
        while i < length
          markers << @adapter.dialect.bind_marker(i)
          i += 1
        end
        markers
      end

      sig { params(column: Codegen::ColumnInfo, value: FixtureValue).returns(PGValue) }
      def encode_value(column, value)
        return nil if value.nil?

        data_type = column.data_type.downcase

        case data_type
        when "boolean", "bool"
          @adapter.encode(BoolBind.new(boolean_value(value)))
        when "smallint", "integer", "bigint", "int", "tinyint"
          @adapter.encode(IntBind.new(integer_value(value)))
        when "real", "double precision", "double", "float"
          @adapter.encode(FloatBind.new(float_value(value)))
        when "numeric", "decimal"
          @adapter.encode(DecimalBind.new(decimal_value(value)))
        when "date"
          @adapter.encode(DateBind.new(date_value(value)))
        when "timestamp without time zone", "timestamp with time zone", "datetime", "timestamp"
          @adapter.encode(TimeBind.new(time_value(value)))
        when "json", "jsonb"
          @adapter.encode(JsonBind.new(json_value(value)))
        else
          @adapter.encode(StrBind.new(value.to_s))
        end
      end

      sig { params(value: FixtureValue).returns(Integer) }
      def integer_value(value)
        return value if value.is_a?(Integer)
        return value.to_i if value.is_a?(String)

        raise HakumiORM::Error, "Fixture integer value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(Float) }
      def float_value(value)
        return value if value.is_a?(Float)
        return value.to_f if value.is_a?(Integer) || value.is_a?(String)

        raise HakumiORM::Error, "Fixture float value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(BigDecimal) }
      def decimal_value(value)
        return value if value.is_a?(BigDecimal)
        return BigDecimal(value) if value.is_a?(String)
        return BigDecimal(value.to_s) if value.is_a?(Integer) || value.is_a?(Float)

        raise HakumiORM::Error, "Fixture decimal value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(Date) }
      def date_value(value)
        return value if value.is_a?(Date)
        return Date.parse(value) if value.is_a?(String)

        raise HakumiORM::Error, "Fixture date value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(Time) }
      def time_value(value)
        return value if value.is_a?(Time)
        return Time.parse(value) if value.is_a?(String)

        raise HakumiORM::Error, "Fixture time value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(T::Boolean) }
      def boolean_value(value)
        return value == true if [true, false].include?(value)
        return true if [1, "1", "true"].include?(value)
        return false if [0, "0", "false"].include?(value)

        raise HakumiORM::Error, "Fixture boolean value is invalid: #{value.inspect}"
      end

      sig { params(value: FixtureValue).returns(Json) }
      def json_value(value)
        return Json.parse(value) if value.is_a?(String)

        Json.new(JSON.generate(value))
      end
    end
  end
end
