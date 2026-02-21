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
          models_dir: T.nilable(String)
        ).void
      end
      def initialize(tables, dialect: nil, output_dir: nil, module_name: nil, models_dir: nil)
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
      end

      sig { void }
      def generate!
        FileUtils.mkdir_p(@output_dir)

        has_many_map = compute_has_many

        @tables.each_value do |table|
          table_dir = File.join(@output_dir, singularize(table.name))
          FileUtils.mkdir_p(table_dir)

          File.write(File.join(table_dir, "schema.rb"), build_schema(table))
          File.write(File.join(table_dir, "record.rb"), build_record(table, has_many_map))
          File.write(File.join(table_dir, "new_record.rb"), build_new_record(table))
          File.write(File.join(table_dir, "relation.rb"), build_relation(table))
        end

        File.write(File.join(@output_dir, "manifest.rb"), build_manifest)

        generate_models! if @models_dir
      end

      private

      sig { void }
      def generate_models!
        models_dir = T.must(@models_dir)
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

      # ERB template locals are inherently heterogeneous (String, Array,
      # Integer, nil, etc. in a single Hash). T.untyped is strictly
      # necessary here as the ERB boundary -- all values fed in are
      # computed from typed methods above this layer.
      sig { params(template_name: String, locals: T::Hash[Symbol, T.untyped]).returns(String) }
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
               **build_find_locals(table, record_cls),
               **build_build_locals(ins_cols, ins_cols.reject(&:nullable), ins_cols.select(&:nullable), record_cls))
      end

      sig { params(table: TableInfo, has_many_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_has_many_assocs(table, has_many_map)
        (has_many_map[table.name] || []).map do |info|
          target_cls = classify(T.must(info[:source_table]))
          {
            method_name: T.must(info[:source_table]),
            relation_class: qualify("#{target_cls}Relation"),
            schema_module: qualify("#{target_cls}Schema"),
            fk_const: T.must(info[:fk_column]).upcase,
            pk_attr: table.primary_key || "id"
          }
        end
      end

      sig { params(table: TableInfo).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
      def build_belongs_to_assocs(table)
        table.foreign_keys.map do |fk|
          fk_col = table.columns.find { |c| c.name == fk.column_name }
          target_cls = classify(fk.foreign_table)
          {
            method_name: singularize(fk.foreign_table),
            record_class: qualify("#{target_cls}Record"),
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
        ).returns(T::Hash[Symbol, T.untyped])
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
          accessor = col.nullable ? "result.get_value(i, #{ci})" : "result.fetch_value(i, #{ci})"
          TypeMap.cast_expression(hakumi_type_for(col), accessor, nullable: col.nullable)
        end
      end

      sig { params(table: TableInfo, _record_cls: String).returns(T::Hash[Symbol, T.untyped]) }
      def build_find_locals(table, _record_cls)
        pk = table.primary_key
        return { find_sql: nil, pk_ruby_type: nil } unless pk

        pk_col = table.columns.find { |c| c.name == pk }
        return { find_sql: nil, pk_ruby_type: nil } unless pk_col

        pk_ht = hakumi_type_for(pk_col)
        select_cols = table.columns.map { |c| @dialect.qualified_name(table.name, c.name) }.join(", ")
        sql = "SELECT #{select_cols} FROM #{@dialect.quote_id(table.name)} " \
              "WHERE #{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)} LIMIT 1"

        { find_sql: sql, pk_ruby_type: pk_ht.ruby_type_string(nullable: false) }
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
                           optional_ins.map { |c| "#{c.name}: nil" }).join(", "),
               **build_insert_locals(table, record_cls))
      end

      sig { params(table: TableInfo, _record_cls: String).returns(T::Hash[Symbol, T.untyped]) }
      def build_insert_locals(table, _record_cls)
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
          bind_list: ins_cols.map { |c| "@#{c.name}" }.join(", ")
        }
      end

      sig { params(table: TableInfo).returns(String) }
      def build_relation(table)
        cls = classify(table.name)

        render("relation",
               module_name: @module_name,
               ind: indent,
               relation_class_name: "#{cls}Relation",
               qualified_record_class: qualify("#{cls}Record"),
               qualified_schema: qualify("#{cls}Schema"))
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
          "#{word[0..-4]}y"
        elsif word.end_with?("ves")
          "#{word[0..-4]}f"
        elsif word.end_with?("ses", "xes", "zes", "ches", "shes")
          T.must(word[0..-3])
        elsif word.end_with?("s") && !word.end_with?("ss", "us", "is")
          T.must(word[0..-2])
        else
          word
        end
      end
    end
  end
end
