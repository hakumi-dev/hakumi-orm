# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { params(contracts_dir: String).void }
      def generate_contracts!(contracts_dir)
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

        render("checkable",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: ins_cols.map { |c| { name: c.name, ruby_type: ruby_type(c) } })
      end

      sig { params(table: TableInfo).returns(String) }
      def build_validated_record(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)

        cols = ins_cols.map { |c| { name: c.name, ruby_type: ruby_type(c) } }

        insert_sql = build_insert_sql(table)
        validated_bind_list = ins_cols.map do |col|
          bind_class = hakumi_type_for(col).bind_class
          "#{bind_class}.new(@record.#{col.name}).pg_value"
        end.join(", ")

        render("validated_record",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: cols,
               insert_sql: insert_sql,
               validated_bind_list: validated_bind_list)
      end

      sig { params(table: TableInfo).returns(T.nilable(String)) }
      def build_insert_sql(table)
        ins_cols = insertable_columns(table)
        return nil if ins_cols.empty?

        col_list = ins_cols.map { |c| @dialect.quote_id(c.name) }.join(", ")
        placeholders = ins_cols.each_with_index.map { |_, i| @dialect.bind_marker(i) }.join(", ")
        sql = "INSERT INTO #{@dialect.quote_id(table.name)} (#{col_list}) VALUES (#{placeholders})"

        if @dialect.supports_returning?
          returning = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")
          sql += " RETURNING #{returning}"
        end

        sql
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

      sig { params(table: TableInfo).returns(String) }
      def build_variant_base(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        render("variant_base",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               all_columns: table.columns.map { |c| { name: c.name, ruby_type: ruby_type(c) } })
      end
    end
  end
end
