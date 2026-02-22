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

      sig { params(tables: T::Hash[String, TableInfo], options: GeneratorOptions).void }
      def initialize(tables, options = GeneratorOptions.new)
        cfg = HakumiORM.config

        resolved_dialect = options.dialect
        if resolved_dialect.nil?
          adapter = cfg.adapter
          raise HakumiORM::Error, "No dialect: set HakumiORM.adapter or pass dialect:" unless adapter

          resolved_dialect = adapter.dialect
        end

        @tables = T.let(tables, T::Hash[String, TableInfo])
        @dialect = T.let(resolved_dialect, Dialect::Base)
        @output_dir = T.let(options.output_dir || cfg.output_dir, String)
        @module_name = T.let(options.module_name || cfg.module_name, T.nilable(String))
        @models_dir = T.let(options.models_dir || cfg.models_dir, T.nilable(String))
        @contracts_dir = T.let(options.contracts_dir || cfg.contracts_dir, T.nilable(String))
        @soft_delete_tables = T.let(options.soft_delete_tables, T::Hash[String, String])
        @created_at_column = T.let(options.created_at_column, T.nilable(String))
        @updated_at_column = T.let(options.updated_at_column, T.nilable(String))

        normalize_column_order!
      end

      sig { void }
      def generate!
        FileUtils.mkdir_p(@output_dir)

        has_many_map = compute_has_many
        has_one_map = compute_has_one
        through_map = compute_has_many_through

        enum_types = collect_enum_types
        generate_enum_files!(enum_types) unless enum_types.empty?

        @tables.each_value do |table|
          table_dir = File.join(@output_dir, singularize(table.name))
          FileUtils.mkdir_p(table_dir)

          File.write(File.join(table_dir, "checkable.rb"), build_checkable(table))
          File.write(File.join(table_dir, "schema.rb"), build_schema(table))
          File.write(File.join(table_dir, "record.rb"), build_record(table, has_many_map, has_one_map, through_map))
          File.write(File.join(table_dir, "new_record.rb"), build_new_record(table))
          File.write(File.join(table_dir, "validated_record.rb"), build_validated_record(table))
          File.write(File.join(table_dir, "base_contract.rb"), build_base_contract(table))
          File.write(File.join(table_dir, "variant_base.rb"), build_variant_base(table))
          File.write(File.join(table_dir, "relation.rb"), build_relation(table, has_many_map, has_one_map))
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
            next if table.unique_columns.include?(fk.column_name)

            list = result[fk.foreign_table] ||= []
            list << { source_table: table.name, fk_column: fk.column_name }
          end
        end
        result
      end

      sig { returns(T::Hash[String, T::Array[T::Hash[Symbol, String]]]) }
      def compute_has_one
        result = T.let({}, T::Hash[String, T::Array[T::Hash[Symbol, String]]])
        @tables.each_value do |table|
          table.foreign_keys.each do |fk|
            next unless table.unique_columns.include?(fk.column_name)

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
          ev = col.enum_values
          field_cls = if ev
                        "::HakumiORM::EnumField[#{qualify(enum_class_name(col.udt_name))}]"
                      else
                        hakumi_type_for(col).field_class
                      end
          qn = escape_ruby_dq(@dialect.qualified_name(table.name, col.name))
          { const: col.name.upcase, field_cls: field_cls, name: col.name, qn: qn }
        end

        render("schema",
               module_name: @module_name,
               ind: indent,
               schema_module_name: "#{classify(table.name)}Schema",
               table_name: table.name,
               fields: fields)
      end

      sig do
        params(
          table: TableInfo,
          has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]],
          has_one_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]],
          through_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]
        ).returns(String)
      end
      def build_record(table, has_many_map, has_one_map, through_map)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)

        col_list = ins_cols.map { |c| @dialect.quote_id(c.name) }.join(", ")
        returning_list = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")

        render("record",
               module_name: @module_name,
               ind: indent,
               record_class_name: qualify(record_cls),
               to_h_value_type: to_h_value_type(table),
               as_json_value_type: as_json_value_type(table),
               columns: table.columns.map { |c| { name: c.name, ruby_type: ruby_type(c), json_expr: json_expr(c) } },
               init_sig_params: table.columns.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
               init_args: table.columns.map { |c| "#{c.name}:" }.join(", "),
               cast_lines: build_cast_lines(table),
               last_cast_index: table.columns.length - 1,
               qualified_relation: qualify("#{cls}Relation"),
               has_many: build_has_many_assocs(table, has_many_map),
               has_one: build_has_one_assocs(table, has_one_map),
               has_many_through: build_has_many_through_assocs(table, through_map),
               belongs_to: build_belongs_to_assocs(table),
               insert_all_prefix: "INSERT INTO #{@dialect.quote_id(table.name)} (#{col_list}) VALUES ",
               insert_all_columns: ins_cols.map { |c| { name: c.name, is_enum: !c.enum_values.nil? } },
               supports_returning: @dialect.supports_returning?,
               returning_cols: returning_list,
               **build_find_locals(table, record_cls),
               **build_delete_locals(table),
               **build_update_locals(table, ins_cols),
               **build_build_locals(ins_cols, ins_cols.reject(&:nullable), ins_cols.select(&:nullable), record_cls))
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

      sig do
        params(
          table: TableInfo,
          has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]],
          has_one_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]
        ).returns(String)
      end
      def build_relation(table, has_many_map, has_one_map)
        cls = classify(table.name)
        hm = build_has_many_assocs(table, has_many_map)
        ho = build_has_one_assocs(table, has_one_map)
        bt = build_belongs_to_assocs(table)
        preloadable = hm.map { |a| { method_name: a[:method_name], relation_class: a[:relation_class] } } +
                      ho.map { |a| { method_name: a[:method_name], relation_class: a[:relation_class] } } +
                      bt.map { |a| { method_name: a[:method_name], relation_class: a[:target_relation] } }

        sd_col = soft_delete_column(table)
        count_sql = "SELECT COUNT(*) FROM #{@dialect.quote_id(table.name)}"
        count_sql += " WHERE #{@dialect.qualified_name(table.name, sd_col)} IS NULL" if sd_col

        render("relation",
               module_name: @module_name,
               ind: indent,
               relation_class_name: "#{cls}Relation",
               qualified_record_class: qualify("#{cls}Record"),
               qualified_schema: qualify("#{cls}Schema"),
               count_sql: count_sql,
               stmt_count_name: "hakumi_#{table.name}_count",
               soft_delete: !sd_col.nil?,
               soft_delete_const: sd_col&.upcase,
               preloadable_assocs: preloadable)
      end

      sig { params(table: TableInfo).returns(String) }
      def build_model(table)
        cls = classify(table.name)

        render("model",
               module_name: @module_name,
               ind: indent,
               model_class_name: qualify(cls),
               record_class_name: qualify("#{cls}Record"),
               relation_class_name: qualify("#{cls}Relation"),
               schema_module: qualify("#{cls}Schema"))
      end

      sig { returns(String) }
      def build_manifest
        enum_types = collect_enum_types
        render("manifest",
               table_names: @tables.keys.map { |n| singularize(n) },
               enum_files: enum_types.keys)
      end

      sig { returns(String) }
      def indent
        @module_name ? "  " : ""
      end

      sig { params(col: ColumnInfo).returns(HakumiType) }
      def hakumi_type_for(col)
        TypeMap.hakumi_type(@dialect.name, col.data_type, col.udt_name)
      end

      sig { void }
      def normalize_column_order!
        @tables.each_value do |table|
          table.columns.sort_by!(&:name)
          table.foreign_keys.sort_by!(&:column_name)
          table.unique_columns.sort!
        end
      end

      sig { params(col: ColumnInfo).returns(String) }
      def ruby_type(col)
        ev = col.enum_values
        if ev
          base = qualify(enum_class_name(col.udt_name))
          col.nullable ? "T.nilable(#{base})" : base
        else
          hakumi_type_for(col).ruby_type_string(nullable: col.nullable)
        end
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

      sig { params(value: String).returns(String) }
      def escape_ruby_dq(value)
        value.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }
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
