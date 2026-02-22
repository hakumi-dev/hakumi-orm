# typed: strict
# frozen_string_literal: true

require "erb"
require "fileutils"

module HakumiORM
  module Codegen
    class Generator
      extend T::Sig

      TEMPLATE_DIR = T.let(
        File.join(File.dirname(File.expand_path(__FILE__)), "templates").freeze,
        String
      )

      sig do
        params(
          tables: T::Hash[String, TableInfo],
          dialect: T.nilable(Dialect::Base),
          output_dir: T.nilable(String),
          module_name: T.nilable(String),
          models_dir: T.nilable(String),
          contracts_dir: T.nilable(String)
        ).void
      end
      def initialize(tables, dialect: nil, output_dir: nil, module_name: nil, models_dir: nil, contracts_dir: nil)
        cfg = HakumiORM.config

        resolved_dialect = dialect
        if resolved_dialect.nil?
          adapter = cfg.adapter
          raise HakumiORM::Error, "No dialect: set HakumiORM.adapter or pass dialect:" unless adapter

          resolved_dialect = adapter.dialect
        end

        @tables = T.let(tables, T::Hash[String, TableInfo])
        @dialect = T.let(resolved_dialect, Dialect::Base)
        @output_dir = T.let(output_dir || cfg.output_dir, String)
        @module_name = T.let(module_name || cfg.module_name, T.nilable(String))
        @models_dir = T.let(models_dir || cfg.models_dir, T.nilable(String))
        @contracts_dir = T.let(contracts_dir || cfg.contracts_dir, T.nilable(String))
      end

      sig { void }
      def generate!
        FileUtils.mkdir_p(@output_dir)

        has_many_map = compute_has_many

        @tables.each_value do |table|
          table_dir = File.join(@output_dir, singularize(table.name))
          FileUtils.mkdir_p(table_dir)

          File.write(File.join(table_dir, "checkable.rb"), build_checkable(table))
          File.write(File.join(table_dir, "schema.rb"), build_schema(table))
          File.write(File.join(table_dir, "record.rb"), build_record(table, has_many_map))
          File.write(File.join(table_dir, "new_record.rb"), build_new_record(table))
          File.write(File.join(table_dir, "validated_record.rb"), build_validated_record(table))
          File.write(File.join(table_dir, "base_contract.rb"), build_base_contract(table))
          File.write(File.join(table_dir, "variant_base.rb"), build_variant_base(table))
          File.write(File.join(table_dir, "relation.rb"), build_relation(table, has_many_map))
        end

        File.write(File.join(@output_dir, "manifest.rb"), build_manifest)

        md = @models_dir
        generate_models!(md) if md
        cd = @contracts_dir
        generate_contracts!(cd) if cd
      end

      private

      sig { params(models_dir: String).void }
      def generate_models!(models_dir)
        FileUtils.mkdir_p(models_dir)

        @tables.each_value do |table|
          model_path = File.join(models_dir, "#{singularize(table.name)}.rb")
          next if File.exist?(model_path)

          File.write(model_path, build_model(table))
        end
      end

      sig { returns(T::Hash[String, T::Array[T::Hash[Symbol, String]]]) }
      def compute_has_many
        result = T.let({}, T::Hash[String, T::Array[T::Hash[Symbol, String]]])
        @tables.each_value do |table|
          table.foreign_keys.each do |fk|
            list = result[fk.foreign_table] ||= []
            list << { source_table: table.name, fk_column: fk.column_name }
          end
        end
        result
      end

      sig { params(template_name: String, locals: T::Hash[Symbol, TemplateLocal]).returns(String) }
      def render(template_name, locals)
        path = File.join(TEMPLATE_DIR, "#{template_name}.rb.erb")
        T.cast(ERB.new(File.read(path), trim_mode: "-").result_with_hash(locals), String)
      end

      sig { params(table: TableInfo).returns(String) }
      def build_schema(table)
        fields = table.columns.map do |col|
          ht = hakumi_type_for(col)
          field_cls = ht.field_class
          qn = @dialect.qualified_name(table.name, col.name).gsub('"', '\\"')
          { const: col.name.upcase, field_cls: field_cls, name: col.name, qn: qn }
        end

        render("schema",
               module_name: @module_name,
               ind: indent,
               schema_module_name: "#{classify(table.name)}Schema",
               table_name: table.name,
               fields: fields)
      end

      sig { params(table: TableInfo, has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(String) }
      def build_record(table, has_many_map)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)

        col_list = ins_cols.map { |c| @dialect.quote_id(c.name) }.join(", ")
        returning_list = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")

        render("record",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: table.columns.map { |c| { name: c.name, ruby_type: ruby_type(c) } },
               init_sig_params: table.columns.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
               init_args: table.columns.map { |c| "#{c.name}:" }.join(", "),
               cast_lines: build_cast_lines(table),
               last_cast_index: table.columns.length - 1,
               qualified_relation: qualify("#{cls}Relation"),
               has_many: build_has_many_assocs(table, has_many_map),
               belongs_to: build_belongs_to_assocs(table),
               insert_all_prefix: "INSERT INTO #{@dialect.quote_id(table.name)} (#{col_list}) VALUES ",
               insert_all_columns: ins_cols.map { |c| { name: c.name } },
               supports_returning: @dialect.supports_returning?,
               returning_cols: returning_list,
               **build_find_locals(table, record_cls),
               **build_build_locals(ins_cols, ins_cols.reject(&:nullable), ins_cols.select(&:nullable), record_cls))
      end

      sig { params(table: TableInfo, has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_has_many_assocs(table, has_many_map)
        pk_col = table.columns.find { |c| c.name == (table.primary_key || "id") }
        pk_type = pk_col ? hakumi_type_for(pk_col).ruby_type_string(nullable: false) : "Integer"

        (has_many_map[table.name] || []).map do |info|
          target_cls = classify(info.fetch(:source_table))
          {
            method_name: info.fetch(:source_table),
            relation_class: qualify("#{target_cls}Relation"),
            record_class: qualify("#{target_cls}Record"),
            schema_module: qualify("#{target_cls}Schema"),
            fk_const: info.fetch(:fk_column).upcase,
            fk_attr: info.fetch(:fk_column),
            pk_attr: table.primary_key || "id",
            pk_ruby_type: pk_type
          }
        end
      end

      sig { params(table: TableInfo).returns(T::Array[BelongsToEntry]) }
      def build_belongs_to_assocs(table)
        table.foreign_keys.map do |fk|
          fk_col = table.columns.find { |c| c.name == fk.column_name }
          target_cls = classify(fk.foreign_table)
          target_table = @tables[fk.foreign_table]
          target_pk = target_table&.primary_key || "id"
          target_pk_col = target_table&.columns&.find { |c| c.name == target_pk }
          target_pk_type = target_pk_col ? hakumi_type_for(target_pk_col).ruby_type_string(nullable: false) : "Integer"
          {
            method_name: singularize(fk.foreign_table),
            record_class: qualify("#{target_cls}Record"),
            target_relation: qualify("#{target_cls}Relation"),
            target_schema: qualify("#{target_cls}Schema"),
            target_pk_const: target_pk.upcase,
            target_pk_attr: target_pk,
            target_pk_type: target_pk_type,
            fk_attr: fk.column_name,
            nullable: fk_col&.nullable || false
          }
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

      sig { params(table: TableInfo).returns(T::Array[String]) }
      def build_cast_lines(table)
        table.columns.each_with_index.map do |col, ci|
          TypeMap.cast_expression(hakumi_type_for(col), "c#{ci}[i]", nullable: col.nullable)
        end
      end

      sig { params(table: TableInfo, _record_cls: String).returns(T::Hash[Symbol, T.nilable(String)]) }
      def build_find_locals(table, _record_cls)
        pk = table.primary_key
        return { find_sql: nil, pk_ruby_type: nil, stmt_find_name: nil } unless pk

        pk_col = table.columns.find { |c| c.name == pk }
        return { find_sql: nil, pk_ruby_type: nil, stmt_find_name: nil } unless pk_col

        pk_ht = hakumi_type_for(pk_col)
        select_cols = table.columns.map { |c| @dialect.qualified_name(table.name, c.name) }.join(", ")
        sql = "SELECT #{select_cols} FROM #{@dialect.quote_id(table.name)} " \
              "WHERE #{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)} LIMIT 1"

        {
          find_sql: sql,
          pk_ruby_type: pk_ht.ruby_type_string(nullable: false),
          stmt_find_name: "hakumi_#{table.name}_find"
        }
      end

      sig { params(table: TableInfo).returns(String) }
      def build_new_record(table)
        cls = classify(table.name)
        record_cls = "#{cls}Record"

        ins_cols = insertable_columns(table)
        required_ins = ins_cols.reject(&:nullable)
        optional_ins = ins_cols.select(&:nullable)

        ordered = required_ins + optional_ins
        cols = ordered.map { |c| { name: c.name, ruby_type: ruby_type(c) } }

        render("new_record",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               columns: cols,
               init_sig_params: ordered.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
               init_args: (required_ins.map { |c| "#{c.name}:" } +
                           optional_ins.map { |c| "#{c.name}: nil" }).join(", "))
      end

      sig { params(table: TableInfo, has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(String) }
      def build_relation(table, has_many_map)
        cls = classify(table.name)
        hm = build_has_many_assocs(table, has_many_map)
        bt = build_belongs_to_assocs(table)
        preloadable = hm.map { |a| { method_name: a[:method_name] } } +
                      bt.map { |a| { method_name: a[:method_name] } }

        count_sql = "SELECT COUNT(*) FROM #{@dialect.quote_id(table.name)}"

        render("relation",
               module_name: @module_name,
               ind: indent,
               relation_class_name: "#{cls}Relation",
               qualified_record_class: qualify("#{cls}Record"),
               qualified_schema: qualify("#{cls}Schema"),
               count_sql: count_sql,
               stmt_count_name: "hakumi_#{table.name}_count",
               preloadable_assocs: preloadable)
      end

      sig { params(table: TableInfo).returns(String) }
      def build_model(table)
        cls = classify(table.name)

        render("model",
               module_name: @module_name,
               ind: indent,
               model_class_name: qualify(cls),
               record_class_name: qualify("#{cls}Record"))
      end

      sig { returns(String) }
      def build_manifest
        render("manifest", table_names: @tables.keys.map { |n| singularize(n) })
      end

      sig { returns(String) }
      def indent
        @module_name ? "  " : ""
      end

      sig { params(col: ColumnInfo).returns(HakumiType) }
      def hakumi_type_for(col)
        TypeMap.hakumi_type(@dialect.name, col.data_type, col.udt_name)
      end

      sig { params(col: ColumnInfo).returns(String) }
      def ruby_type(col)
        hakumi_type_for(col).ruby_type_string(nullable: col.nullable)
      end

      sig { params(table: TableInfo).returns(T::Array[ColumnInfo]) }
      def insertable_columns(table)
        table.columns.reject do |c|
          c.default&.start_with?("nextval(") || false
        end
      end

      sig { params(name: String).returns(String) }
      def qualify(name)
        @module_name ? "#{@module_name}::#{name}" : name
      end

      sig { params(table_name: String).returns(String) }
      def classify(table_name)
        singularize(table_name).split("_").map(&:capitalize).join
      end

      sig { params(word: String).returns(String) }
      def singularize(word)
        if word.end_with?("ies")
          "#{word.delete_suffix("ies")}y"
        elsif word.end_with?("ves")
          "#{word.delete_suffix("ves")}f"
        elsif word.end_with?("ses", "xes", "zes", "ches", "shes")
          word.delete_suffix("es")
        elsif word.end_with?("s") && !word.end_with?("ss", "us", "is")
          word.delete_suffix("s")
        else
          word
        end
      end
    end
  end
end
