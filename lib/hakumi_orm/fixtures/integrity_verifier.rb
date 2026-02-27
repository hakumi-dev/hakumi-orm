# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Fixtures
    # Verifies foreign-key integrity for already loaded fixture rows.
    class IntegrityVerifier
      extend T::Sig

      sig do
        params(
          adapter: Adapter::Base,
          tables: T::Hash[String, Codegen::TableInfo]
        ).void
      end
      def initialize(adapter:, tables:)
        @adapter = T.let(adapter, Adapter::Base)
        @tables = T.let(tables, T::Hash[String, Codegen::TableInfo])
      end

      sig { params(table_names: T::Array[String]).void }
      def verify!(table_names)
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

      private

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
    end
  end
end
