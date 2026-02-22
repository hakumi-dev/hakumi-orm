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
          if timestamp_auto_column?(col)
            "#{hakumi_type_for(col).bind_class}.new(::Time.now).pg_value"
          elsif col.enum_values
            "::HakumiORM::StrBind.new(T.cast(@record.#{col.name}.serialize, String)).pg_value"
          else
            "#{hakumi_type_for(col).bind_class}.new(@record.#{col.name}).pg_value"
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

        has_lv = lock_version_column(table)
        user_cols = has_lv ? ins_cols.reject { |c| c.name == "lock_version" } : ins_cols
        sql = build_update_sql(table, user_cols, pk, lock_version: !has_lv.nil?)

        {
          update_sql: sql,
          update_sig_params: user_cols.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
          update_defaults: user_cols.map { |c| "#{c.name}: @#{c.name}" }.join(", "),
          update_bind_list: build_update_bind_list(user_cols),
          update_ins_cols: user_cols.map { |c| { name: c.name } },
          has_lock_version: !has_lv.nil?
        }
      end

      sig do
        params(table: TableInfo, user_cols: T::Array[ColumnInfo], pk: String, lock_version: T::Boolean).returns(String)
      end
      def build_update_sql(table, user_cols, pk, lock_version:)
        set_parts = user_cols.each_with_index.map do |col, idx|
          "#{@dialect.quote_id(col.name)} = #{@dialect.bind_marker(idx)}"
        end
        set_parts << "#{@dialect.quote_id("lock_version")} = #{@dialect.quote_id("lock_version")} + 1" if lock_version

        next_idx = user_cols.length
        pk_marker = @dialect.bind_marker(next_idx)
        where = "#{@dialect.qualified_name(table.name, pk)} = #{pk_marker}"
        if lock_version
          lv_marker = @dialect.bind_marker(next_idx + 1)
          where += " AND #{@dialect.qualified_name(table.name, "lock_version")} = #{lv_marker}"
        end

        returning = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")
        sql = "UPDATE #{@dialect.quote_id(table.name)} SET #{set_parts.join(", ")} WHERE #{where}"
        sql += " RETURNING #{returning}" if @dialect.supports_returning?
        sql
      end

      sig { params(user_cols: T::Array[ColumnInfo]).returns(String) }
      def build_update_bind_list(user_cols)
        user_cols.map do |col|
          if col.name == "updated_at" && hakumi_type_for(col) == Codegen::HakumiType::Timestamp
            "#{hakumi_type_for(col).bind_class}.new(::Time.now).pg_value"
          elsif col.enum_values
            "::HakumiORM::StrBind.new(T.cast(#{col.name}.serialize, String)).pg_value"
          else
            "#{hakumi_type_for(col).bind_class}.new(#{col.name}).pg_value"
          end
        end.join(", ")
      end

      sig { params(table: TableInfo).returns(T.nilable(ColumnInfo)) }
      def lock_version_column(table)
        table.columns.find do |col|
          col.name == "lock_version" && hakumi_type_for(col) == Codegen::HakumiType::Integer
        end
      end

      sig do
        params(
          ins_cols: T::Array[ColumnInfo],
          required_ins: T::Array[ColumnInfo],
          optional_ins: T::Array[ColumnInfo],
          _record_cls: String
        ).returns(T::Hash[Symbol, T.nilable(String)])
      end
      def build_build_locals(ins_cols, required_ins, optional_ins, _record_cls)
        return { build_sig_params: nil } if ins_cols.empty?

        ordered = required_ins + optional_ins
        {
          build_sig_params: ordered.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
          build_args: (required_ins.map { |c| "#{c.name}:" } +
                       optional_ins.map { |c| "#{c.name}: nil" }).join(", "),
          build_forward: ins_cols.map { |c| "#{c.name}: #{c.name}" }.join(", ")
        }
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

      sig { params(col: ColumnInfo).returns(String) }
      def json_expr(col)
        if col.enum_values
          ivar = "@#{col.name}"
          col.nullable ? "#{ivar}&.serialize&.to_s" : "#{ivar}.serialize.to_s"
        else
          hakumi_type_for(col).as_json_expr("@#{col.name}", nullable: col.nullable)
        end
      end

      sig { params(table: TableInfo).returns(String) }
      def as_json_value_type(table)
        types = table.columns.map { |c| json_ruby_type(c) }.uniq.sort
        types.length == 1 ? types.fetch(0) : "T.nilable(T.any(#{types.join(", ")}))"
      end

      sig { params(col: ColumnInfo).returns(String) }
      def json_ruby_type(col)
        return "String" if col.enum_values

        ht = hakumi_type_for(col)
        case ht
        when HakumiType::Integer                then "Integer"
        when HakumiType::Float                  then "Float"
        when HakumiType::Boolean                then "T::Boolean"
        when HakumiType::String, HakumiType::Uuid,
             HakumiType::Decimal, HakumiType::Timestamp,
             HakumiType::Date, HakumiType::Json then "String"
        else T.absurd(ht)
        end
      end

      sig { params(table: TableInfo).returns(String) }
      def build_variant_base(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        render("variant_base",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               to_h_value_type: to_h_value_type(table),
               as_json_value_type: as_json_value_type(table),
               all_columns: table.columns.map { |c| { name: c.name, ruby_type: ruby_type(c) } })
      end
    end
  end
end
