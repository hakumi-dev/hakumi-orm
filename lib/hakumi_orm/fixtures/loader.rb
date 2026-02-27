# typed: strict
# frozen_string_literal: true

require "erb"
require "yaml"
require "date"
require "bigdecimal"
require "json"

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

      sig { params(adapter: Adapter::Base, tables: T::Hash[String, Codegen::TableInfo]).void }
      def initialize(adapter:, tables:)
        @adapter = T.let(adapter, Adapter::Base)
        @tables = T.let(tables, T::Hash[String, Codegen::TableInfo])
      end

      sig do
        params(
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String])
        ).returns(Integer)
      end
      def load!(base_path:, fixtures_dir: nil, only_names: nil)
        files = fixture_files(base_path: base_path, fixtures_dir: fixtures_dir, only_names: only_names)
        loaded_tables = T.let({}, T::Hash[String, T::Boolean])
        files.each do |file|
          table_name = table_name_for_file(base_path, file, fixtures_dir: fixtures_dir)
          table = @tables[table_name]
          next unless table

          rows = parse_fixture_rows(file)
          replace_table_rows!(table, rows)
          loaded_tables[table_name] = true
        end
        loaded_tables.keys.size
      end

      private

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

      sig { params(path: String).returns(T::Array[T::Hash[String, FixtureValue]]) }
      def parse_fixture_rows(path)
        src = File.read(path)
        rendered = ERB.new(src).result
        parsed = YAML.safe_load(
          rendered,
          permitted_classes: [Date, Time, BigDecimal, Symbol],
          aliases: true
        )
        return [] unless parsed.is_a?(Hash)

        parsed.each_with_object([]) do |(_label, attrs), acc|
          next unless attrs.is_a?(Hash)

          acc << normalize_row(attrs)
        end
      end

      sig { params(attrs: T::Hash[T.any(String, Symbol), FixtureValue]).returns(T::Hash[String, FixtureValue]) }
      def normalize_row(attrs)
        row = T.let({}, T::Hash[String, FixtureValue])
        attrs.each { |k, v| row[k.to_s] = v }
        row
      end

      sig { params(table: Codegen::TableInfo, rows: T::Array[T::Hash[String, FixtureValue]]).void }
      def replace_table_rows!(table, rows)
        delete_all_sql = "DELETE FROM #{@adapter.dialect.quote_id(table.name)}"
        @adapter.exec(delete_all_sql).close
        return if rows.empty?

        rows.each { |row| insert_row!(table, row) }
      end

      sig { params(table: Codegen::TableInfo, row: T::Hash[String, FixtureValue]).void }
      def insert_row!(table, row)
        columns, values = row_columns_and_values(table, row)

        return if columns.empty?

        markers = bind_markers(values.length)
        sql = "INSERT INTO #{@adapter.dialect.quote_id(table.name)} (#{columns.join(", ")}) VALUES (#{markers.join(", ")})"
        @adapter.exec_params(sql, values).close
      end

      sig { params(table: Codegen::TableInfo, row: T::Hash[String, FixtureValue]).returns([T::Array[String], T::Array[PGValue]]) }
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
        return true if value == true
        return false if value == false
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
