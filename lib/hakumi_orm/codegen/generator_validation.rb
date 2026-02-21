# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { void }
      def generate_contracts!
        contracts_dir = T.must(@contracts_dir)
        FileUtils.mkdir_p(contracts_dir)

        @tables.each_value do |table|
          contract_path = File.join(contracts_dir, "#{singularize(table.name)}_contract.rb")
          next if File.exist?(contract_path)

          File.write(contract_path, build_contract(table))
        end
      end

      sig { params(table: TableInfo).returns(String) }
      def build_checkable(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)
        required_ins = ins_cols.reject(&:nullable)
        optional_ins = ins_cols.select(&:nullable)
        ordered = required_ins + optional_ins

        render("checkable",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: ordered.map { |c| { name: c.name, ruby_type: ruby_type(c) } })
      end

      sig { params(table: TableInfo).returns(String) }
      def build_validated_record(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)
        required_ins = ins_cols.reject(&:nullable)
        optional_ins = ins_cols.select(&:nullable)
        ordered = required_ins + optional_ins

        render("validated_record",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: ordered.map { |c| { name: c.name, ruby_type: ruby_type(c) } },
               **build_validated_insert_locals(table))
      end

      sig { params(table: TableInfo).returns(String) }
      def build_base_contract(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        render("base_contract",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls))
      end

      sig { params(table: TableInfo).returns(String) }
      def build_contract(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        render("contract",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls))
      end

      sig { params(table: TableInfo).returns(T::Hash[Symbol, T.nilable(String)]) }
      def build_validated_insert_locals(table)
        ins_cols = insertable_columns(table)
        return { insert_sql: nil } if ins_cols.empty?

        col_list = ins_cols.map { |c| @dialect.quote_id(c.name) }.join(", ")
        markers = ins_cols.each_with_index.map { |_, i| @dialect.bind_marker(i) }.join(", ")
        sql = "INSERT INTO #{@dialect.quote_id(table.name)} (#{col_list}) VALUES (#{markers})"

        if @dialect.supports_returning?
          returning_cols = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")
          sql += " RETURNING #{returning_cols}"
        end

        {
          insert_sql: sql,
          validated_bind_list: ins_cols.map { |c| "@record.#{c.name}" }.join(", ")
        }
      end
    end
  end
end
