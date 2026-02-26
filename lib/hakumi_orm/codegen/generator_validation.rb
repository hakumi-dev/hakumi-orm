# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { void }
      def generate_contracts!
        root_dir = @generation_plan.contracts_root_dir
        return unless root_dir

        @file_writer.mkdir_p(root_dir)

        @tables.each_value do |table|
          next if @internal_tables.include?(table.name)

          contract_path = @generation_plan.contract_stub_path(singularize(table.name))
          next unless contract_path

          @file_writer.write_if_missing(contract_path, build_contract(table))
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
               record_class_name: record_cls,
               columns: ins_cols.map { |c| { name: c.name, ruby_type: ruby_type(c) } })
      end

      sig { params(table: TableInfo).returns(String) }
      def build_validated_record(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)

        cols = ins_cols.map { |c| { name: c.name, ruby_type: ruby_type(c) } }
        validated_bind_list = validated_bind_list_for(ins_cols)

        pk = table.primary_key
        pk_col = pk ? table.columns.find { |c| c.name == pk } : nil
        has_auto_pk = pk_col && !ins_cols.include?(pk_col)

        refetch_sql, refetch_bind_list = build_refetch_locals(table, ins_cols, pk, pk_col, has_auto_pk)

        render("validated_record",
               module_name: @module_name,
               ind: indent,
               record_class_name: record_cls,
               columns: cols,
               insert_sql: build_insert_sql(table),
               validated_bind_list: validated_bind_list,
               supports_returning: @dialect.supports_returning?,
               has_auto_pk: has_auto_pk,
               refetch_sql: refetch_sql,
               refetch_bind_list: refetch_bind_list)
      end

      sig { params(ins_cols: T::Array[ColumnInfo]).returns(String) }
      def validated_bind_list_for(ins_cols)
        ins_cols.map do |col|
          if auto_timestamp_on_insert?(col)
            "adapter.encode(#{hakumi_type_for(col).bind_class}.new(::Time.now))"
          elsif col.enum_values
            enum_bind_expr("@record.#{col.name}", col)
          else
            nullable_bind_expr(col, "@record.#{col.name}")
          end
        end.join(", ")
      end

      sig do
        params(
          table: TableInfo, ins_cols: T::Array[ColumnInfo],
          pk: T.nilable(String), pk_col: T.nilable(ColumnInfo), has_auto_pk: T.nilable(T::Boolean)
        ).returns([T.nilable(String), T.nilable(String)])
      end
      def build_refetch_locals(table, ins_cols, pk, pk_col, has_auto_pk)
        return [nil, nil] if @dialect.supports_returning? || has_auto_pk

        all_cols = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")
        tbl = @dialect.quote_id(table.name)

        if pk && pk_col
          where = "#{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)}"
          ["SELECT #{all_cols} FROM #{tbl} WHERE #{where} LIMIT 1",
           nullable_bind_expr(pk_col, "@record.#{pk}")]
        else
          parts = ins_cols.each_with_index.map do |c, i|
            "#{@dialect.qualified_name(table.name, c.name)} = #{@dialect.bind_marker(i)}"
          end
          ["SELECT #{all_cols} FROM #{tbl} WHERE #{parts.join(" AND ")} LIMIT 1",
           ins_cols.map { |c| nullable_bind_expr(c, "@record.#{c.name}") }.join(", ")]
        end
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
               record_class_name: record_cls)
      end

      sig { params(table: TableInfo).returns(String) }
      def build_contract(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        render("contract",
               module_name: @module_name,
               ind: indent,
               record_class_name: record_cls)
      end

      sig { params(table: TableInfo, ins_cols: T::Array[ColumnInfo]).returns(T::Hash[Symbol, TemplateLocal]) }
      def build_update_locals(table, ins_cols)
        pk = table.primary_key
        return { update_sql: nil } unless pk
        return { update_sql: nil } if ins_cols.empty?

        has_lv = lock_version_column(table)
        user_cols = has_lv ? ins_cols.reject { |c| c.name == "lock_version" } : ins_cols
        tbl = @dialect.quote_id(table.name)

        build_update_hash(table, user_cols, tbl, has_lv, pk)
      end

      sig do
        params(table: TableInfo, user_cols: T::Array[ColumnInfo], tbl: String,
               has_lv: T.nilable(ColumnInfo), pk: String).returns(T::Hash[Symbol, TemplateLocal])
      end
      def build_update_hash(table, user_cols, tbl, has_lv, pk)
        returning = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")

        {
          update_sql: tbl, update_table: tbl, update_returning: returning,
          update_sig_params: user_cols.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
          update_defaults: user_cols.map { |c| "#{c.name}: @#{c.name}" }.join(", "),
          update_ins_cols: user_cols.map { |c| { name: c.name } },
          update_columns: build_update_column_descs(user_cols),
          update_pk_where: @dialect.qualified_name(table.name, pk),
          supports_positional_binds: @dialect.is_a?(HakumiORM::Dialect::Postgresql),
          **build_lv_locals(table.name, has_lv)
        }
      end

      sig { params(user_cols: T::Array[ColumnInfo]).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
      def build_update_column_descs(user_cols)
        user_cols.map do |col|
          { name: col.name, quoted_name: @dialect.quote_id(col.name),
            bind_expr: update_col_bind_expr(col), auto_ts: auto_timestamp_on_update?(col) }
        end
      end

      sig { params(table_name: String, has_lv: T.nilable(ColumnInfo)).returns(T::Hash[Symbol, TemplateLocal]) }
      def build_lv_locals(table_name, has_lv)
        lv_quoted = has_lv ? @dialect.quote_id("lock_version") : nil
        {
          update_lv_set: lv_quoted ? "#{lv_quoted} = #{lv_quoted} + 1" : nil,
          update_lv_where: has_lv ? @dialect.qualified_name(table_name, "lock_version") : nil,
          has_lock_version: !has_lv.nil?
        }
      end

      sig { params(col: ColumnInfo).returns(String) }
      def update_col_bind_expr(col)
        if col.enum_values
          enum_bind_expr("val", col)
        else
          nullable_bind_expr(col, "val")
        end
      end

      sig { params(accessor: String, col: ColumnInfo).returns(String) }
      def enum_bind_expr(accessor, col)
        if @integer_backed_enums.include?(col.udt_name)
          "adapter.encode(::HakumiORM::IntBind.new(#{accessor}.serialize))"
        else
          "adapter.encode(::HakumiORM::StrBind.new(#{accessor}.serialize))"
        end
      end

      sig { params(col: ColumnInfo, accessor: String).returns(String) }
      def nullable_bind_expr(col, accessor)
        bind_cls = hakumi_type_for(col).bind_class
        if col.nullable
          "((_hv = #{accessor}).nil? ? nil : adapter.encode(#{bind_cls}.new(_hv)))"
        else
          "adapter.encode(#{bind_cls}.new(#{accessor}))"
        end
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
      def auto_timestamp_on_insert?(col)
        [@created_at_column, @updated_at_column].include?(col.name) &&
          hakumi_type_for(col) == Codegen::HakumiType::Timestamp
      end

      sig { params(col: ColumnInfo).returns(T::Boolean) }
      def auto_timestamp_on_update?(col)
        col.name == @updated_at_column && hakumi_type_for(col) == Codegen::HakumiType::Timestamp
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
          if @integer_backed_enums.include?(col.udt_name)
            col.nullable ? "#{ivar}&.serialize" : "#{ivar}.serialize"
          else
            col.nullable ? "#{ivar}&.serialize&.to_s" : "#{ivar}.serialize.to_s"
          end
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
        if col.enum_values
          return @integer_backed_enums.include?(col.udt_name) ? "Integer" : "String"
        end

        ht = hakumi_type_for(col)
        case ht
        when HakumiType::Integer                then "Integer"
        when HakumiType::Float                  then "Float"
        when HakumiType::Boolean                then "T::Boolean"
        when HakumiType::String, HakumiType::Uuid,
             HakumiType::Decimal, HakumiType::Timestamp,
             HakumiType::Date, HakumiType::Json,
             HakumiType::IntegerArray, HakumiType::StringArray,
             HakumiType::FloatArray, HakumiType::BooleanArray then "String"
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
               record_class_name: record_cls,
               to_h_value_type: to_h_value_type(table),
               as_json_value_type: as_json_value_type(table),
               all_columns: table.columns.map { |c| { name: c.name, ruby_type: record_ruby_type(table, c) } })
      end
    end
  end
end
