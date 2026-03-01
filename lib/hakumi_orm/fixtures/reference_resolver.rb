# typed: strict
# frozen_string_literal: true

require "zlib"
require_relative "types"

module HakumiORM
  module Fixtures
    # Resolves fixture label references and dependency ordering.
    class ReferenceResolver
      extend T::Sig

      sig { params(tables: T::Hash[String, Codegen::TableInfo]).void }
      def initialize(tables:)
        @tables = T.let(tables, T::Hash[String, Codegen::TableInfo])
      end

      sig do
        params(
          table: Codegen::TableInfo,
          fixture_label: String,
          row: Types::FixtureRow,
          rows_by_table: Types::LoadedFixtures
        ).returns(T::Array[Types::FixtureRow])
      end
      def expand_row_fk_references(table:, fixture_label:, row:, rows_by_table:)
        expanded = T.let([row.dup], T::Array[Types::FixtureRow])
        table.foreign_keys.each do |fk|
          next_rows = T.let([], T::Array[Types::FixtureRow])
          expanded.each do |current|
            map_association_label_to_fk!(current, fk)
            labels = label_list_for_reference(current[fk.column_name])
            if labels.nil?
              next_rows << current
              next
            end

            labels.each do |label|
              copy = current.dup
              copy[fk.column_name] = resolve_reference_value(fk, label, rows_by_table)
              next_rows << copy
            end
          end
          expanded = next_rows
        end

        adjust_auto_primary_keys_for_expansion(table, fixture_label, expanded)
      end

      sig { params(table_names: T::Array[String]).returns(T::Array[String]) }
      def insertion_order(table_names)
        remaining = table_names.sort
        done = T.let({}, T::Hash[String, T::Boolean])
        ordered = T.let([], T::Array[String])

        Kernel.loop do
          progress = T.let(false, T::Boolean)
          remaining.reject! do |table_name|
            table = @tables[table_name]
            deps = if table
                     table.foreign_keys.map(&:foreign_table).select { |dep| table_names.include?(dep) && dep != table_name }
                   else
                     []
                   end

            ready = deps.all? { |dep| done[dep] }
            if ready
              ordered << table_name
              done[table_name] = true
              progress = true
              true
            else
              false
            end
          end

          break if remaining.empty?
          break unless progress
        end

        ordered.concat(remaining)
      end

      private

      sig do
        params(
          table: Codegen::TableInfo,
          fixture_label: String,
          rows: T::Array[Types::FixtureRow]
        ).returns(T::Array[Types::FixtureRow])
      end
      def adjust_auto_primary_keys_for_expansion(table, fixture_label, rows)
        pk = table.primary_key
        return rows unless pk

        pk_column = table.columns.find { |c| c.name == pk }
        return rows unless pk_column && integer_column?(pk_column)
        return rows if rows.length <= 1

        base_id = fixture_id(fixture_label)
        base_count = rows.count { |r| r[pk] == base_id }
        return rows if base_count <= 1

        seen_base = T.let(0, Integer)
        rows.map.with_index do |r, idx|
          next r unless r[pk] == base_id

          seen_base += 1
          next r if seen_base == 1

          dup = r.dup
          dup[pk] = fixture_id("#{fixture_label}:#{idx}")
          dup
        end
      end

      sig { params(row: Types::FixtureRow, fk: Codegen::ForeignKeyInfo).void }
      def map_association_label_to_fk!(row, fk)
        return unless fk.column_name.end_with?("_id")

        assoc_key = fk.column_name.delete_suffix("_id")
        return unless row.key?(assoc_key)
        return if row.key?(fk.column_name)

        row[fk.column_name] = row.delete(assoc_key)
      end

      sig { params(value: Types::FixtureValue).returns(T.nilable(T::Array[String])) }
      def label_list_for_reference(value)
        case value
        when String
          return value.split(",").map(&:strip).reject(&:empty?) if value.include?(",")

          [value]
        when Symbol
          [value.to_s]
        when Array
          labels = value.filter_map do |entry|
            if entry.is_a?(String)
              entry
            elsif entry.is_a?(Symbol)
              entry.to_s
            end
          end
          labels.empty? ? nil : labels
        end
      end

      sig do
        params(
          fk: Codegen::ForeignKeyInfo,
          label: String,
          rows_by_table: Types::LoadedFixtures
        ).returns(Types::FixtureValue)
      end
      def resolve_reference_value(fk, label, rows_by_table)
        foreign_rows = rows_by_table[fk.foreign_table]
        if foreign_rows
          referenced = foreign_rows[label]
          if referenced
            foreign_table = @tables[fk.foreign_table]
            if foreign_table
              pk = foreign_table.primary_key
              return referenced[pk] if pk && referenced.key?(pk)
            end
          end
        end

        foreign_table = @tables[fk.foreign_table]
        if foreign_table&.primary_key
          pk_column = foreign_table.columns.find { |col| col.name == foreign_table.primary_key }
          return fixture_id(label) if pk_column && integer_column?(pk_column)
        end

        label
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
    end
  end
end
