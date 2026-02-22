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
          if timestamp_auto_column?(col)
            "#{bind_class}.new(::Time.now).pg_value"
          else
            "#{bind_class}.new(@record.#{col.name}).pg_value"
          end
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

      sig { params(table: TableInfo, ins_cols: T::Array[ColumnInfo]).returns(T::Hash[Symbol, TemplateLocal]) }
      def build_update_locals(table, ins_cols)
        pk = table.primary_key
        return { update_sql: nil } unless pk
        return { update_sql: nil } if ins_cols.empty?

        sql = build_update_sql(table, ins_cols, pk)

        {
          update_sql: sql,
          update_sig_params: ins_cols.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
          update_defaults: ins_cols.map { |c| "#{c.name}: @#{c.name}" }.join(", "),
          update_bind_list: build_update_bind_list(ins_cols),
          update_ins_cols: ins_cols.map { |c| { name: c.name } }
        }
      end

      sig { params(table: TableInfo, ins_cols: T::Array[ColumnInfo], pk: String).returns(String) }
      def build_update_sql(table, ins_cols, pk)
        set_parts = ins_cols.each_with_index.map { |c, i| "#{@dialect.quote_id(c.name)} = #{@dialect.bind_marker(i)}" }
        pk_marker = @dialect.bind_marker(ins_cols.length)
        returning = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")

        sql = "UPDATE #{@dialect.quote_id(table.name)} SET #{set_parts.join(", ")} " \
              "WHERE #{@dialect.qualified_name(table.name, pk)} = #{pk_marker}"
        sql += " RETURNING #{returning}" if @dialect.supports_returning?
        sql
      end

      sig { params(ins_cols: T::Array[ColumnInfo]).returns(String) }
      def build_update_bind_list(ins_cols)
        ins_cols.map do |col|
          bind_class = hakumi_type_for(col).bind_class
          if col.name == "updated_at" && hakumi_type_for(col) == Codegen::HakumiType::Timestamp
            "#{bind_class}.new(::Time.now).pg_value"
          else
            "#{bind_class}.new(#{col.name}).pg_value"
          end
        end.join(", ")
      end

      sig { params(table: TableInfo).returns(T::Hash[Symbol, T.nilable(String)]) }
      def build_delete_locals(table)
        pk = table.primary_key
        return { delete_sql: nil, pk_attr: nil } unless pk

        sql = "DELETE FROM #{@dialect.quote_id(table.name)} WHERE #{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)}"
        { delete_sql: sql, pk_attr: pk }
      end

      sig { params(col: ColumnInfo).returns(T::Boolean) }
      def timestamp_auto_column?(col)
        TIMESTAMP_AUTO_NAMES.include?(col.name) && hakumi_type_for(col) == Codegen::HakumiType::Timestamp
      end

      sig { params(table: TableInfo).returns(String) }
      def to_h_value_type(table)
        types = table.columns.map { |c| ruby_type(c) }.uniq.sort
        types.length == 1 ? types.fetch(0) : "T.any(#{types.join(", ")})"
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
