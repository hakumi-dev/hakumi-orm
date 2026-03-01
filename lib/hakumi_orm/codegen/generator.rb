# typed: strict
# frozen_string_literal: true

# Internal component for codegen/generator.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class Generator
      extend T::Sig

      ENUM_COLUMN_TYPE = T.let(HakumiType::Integer, HakumiType)

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
        @custom_associations = T.let(options.custom_associations, T::Hash[String, T::Array[CustomAssociation]])
        @user_enums = T.let(options.user_enums, T::Hash[String, T::Array[EnumDefinition]])
        @internal_tables = T.let(options.internal_tables.to_set, T::Set[String])
        @schema_fingerprint = T.let(options.schema_fingerprint, T.nilable(String))
        @integer_backed_enums = T.let(Set.new, T::Set[String])
        @generation_plan = T.let(
          GenerationPlan.new(
            output_dir: @output_dir,
            models_dir: @models_dir,
            contracts_dir: @contracts_dir,
            module_name: @module_name
          ),
          GenerationPlan
        )
        @template_renderer = T.let(TemplateRenderer.new, TemplateRenderer)
        @file_writer = T.let(FileWriter.new, FileWriter)

        inject_user_enums!
        normalize_column_order!
      end

      sig { void }
      def generate!
        @file_writer.mkdir_p(@generation_plan.output_dir)

        has_many_map = compute_has_many
        has_one_map = compute_has_one
        through_map = compute_has_many_through

        fk_names = build_fk_assoc_names(has_many_map, has_one_map)
        validate_custom_assocs!(@custom_associations, fk_names) unless @custom_associations.empty?

        enum_types = collect_enum_types
        generate_enum_files!(enum_types) unless enum_types.empty?

        @tables.each_value do |table|
          singular = singularize(table.name)
          table_dir = @generation_plan.table_dir(singular)
          @file_writer.mkdir_p(table_dir)

          @file_writer.write(@generation_plan.table_file_path(singular, "schema.rb"), build_schema(table))
          next if @internal_tables.include?(table.name)

          @file_writer.write(@generation_plan.table_file_path(singular, "checkable.rb"), build_checkable(table))
          @file_writer.write(
            @generation_plan.table_file_path(singular, "record.rb"),
            build_record(table, has_many_map, has_one_map, through_map)
          )
          @file_writer.write(@generation_plan.table_file_path(singular, "new_record.rb"), build_new_record(table))
          @file_writer.write(@generation_plan.table_file_path(singular, "validated_record.rb"), build_validated_record(table))
          @file_writer.write(@generation_plan.table_file_path(singular, "base_contract.rb"), build_base_contract(table))
          @file_writer.write(@generation_plan.table_file_path(singular, "variant_base.rb"), build_variant_base(table))
          @file_writer.write(@generation_plan.table_file_path(singular, "relation.rb"), build_relation(table, has_many_map, has_one_map))
        end

        @file_writer.write(@generation_plan.manifest_path, build_manifest)

        if @generation_plan.models_root_dir
          generate_models!
          annotate_models!(has_many_map, has_one_map, through_map)
        end
        generate_contracts! if @generation_plan.contracts_root_dir
      end

      private

      sig { void }
      def generate_models!
        root_dir = @generation_plan.models_root_dir
        return unless root_dir

        @file_writer.mkdir_p(root_dir)

        @tables.each_value do |table|
          next if @internal_tables.include?(table.name)

          model_path = @generation_plan.model_stub_path(singularize(table.name))
          next unless model_path

          @file_writer.write_if_missing(model_path, build_model(table))
        end
      end

      sig { returns(AssocMap) }
      def compute_has_many
        result = T.let({}, AssocMap)
        @tables.each_value do |table|
          table.foreign_keys.each do |fk|
            next if table.unique_columns.include?(fk.column_name)

            list = result[fk.foreign_table] ||= []
            list << { source_table: table.name, fk_column: fk.column_name }
          end
        end
        result
      end

      sig { returns(AssocMap) }
      def compute_has_one
        result = T.let({}, AssocMap)
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
        @template_renderer.render(template_name, locals)
      end

      sig { params(table: TableInfo).returns(String) }
      def build_schema(table)
        fields = table.columns.map do |col|
          ev = col.enum_values
          field_cls = if ev
                        base = @integer_backed_enums.include?(col.udt_name) ? "IntEnumField" : "EnumField"
                        "::HakumiORM::#{base}[#{qualify(enum_class_name(col.udt_name))}]"
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
          has_many_map: AssocMap,
          has_one_map: AssocMap,
          through_map: AssocMap
        ).returns(String)
      end
      def build_record(table, has_many_map, has_one_map, through_map)
        cls = classify(table.name)
        record_cls = "#{cls}Record"
        ins_cols = insertable_columns(table)

        col_list = ins_cols.map { |c| @dialect.quote_id(c.name) }.join(", ")
        returning_list = table.columns.map { |c| @dialect.quote_id(c.name) }.join(", ")

        hm = build_has_many_assocs(table, has_many_map) + build_custom_has_many(table, @custom_associations)
        ho = build_has_one_assocs(table, has_one_map) + build_custom_has_one(table, @custom_associations)
        direct_names = (hm + ho).to_set { |a| a[:method_name] }
        hmt = build_has_many_through_assocs(table, through_map).reject { |a| direct_names.include?(a[:method_name]) }

        render("record",
               module_name: @module_name,
               ind: indent,
               record_class_name: record_cls,
               to_h_value_type: to_h_value_type(table),
               as_json_value_type: as_json_value_type(table),
               columns: table.columns.map { |c| { name: c.name, ruby_type: record_ruby_type(table, c), json_expr: json_expr(c) } },
               init_sig_params: table.columns.map { |c| "#{c.name}: #{record_ruby_type(table, c)}" }.join(", "),
               init_args: table.columns.map { |c| "#{c.name}:" }.join(", "),
               cast_lines: build_cast_lines(table),
               pg_decoders: build_pg_decoders(table),
               last_cast_index: table.columns.length - 1,
               qualified_relation: qualify("#{cls}Relation"),
               qualified_schema: qualify("#{cls}Schema"),
               has_many: hm,
               has_one: ho,
               has_many_through: hmt,
               belongs_to: build_belongs_to_assocs(table),
               insert_all_prefix: "INSERT INTO #{@dialect.quote_id(table.name)} (#{col_list}) VALUES ",
               insert_all_columns: build_insert_all_columns(ins_cols),
               supports_returning: @dialect.supports_returning?,
               returning_cols: returning_list,
               insert_all_table: @dialect.quote_id(table.name),
               insert_all_pk: (pk = table.primary_key) ? @dialect.quote_id(pk) : nil,
               enum_predicates: build_enum_predicates(table),
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
        required_ins, optional_ins = ins_cols.partition { |col| !col.nullable }

        ordered = required_ins + optional_ins
        cols = ordered.map { |c| { name: c.name, ruby_type: ruby_type(c) } }

        render("new_record",
               module_name: @module_name,
               ind: indent,
               record_class_name: record_cls,
               columns: cols,
               init_sig_params: ordered.map { |c| "#{c.name}: #{ruby_type(c)}" }.join(", "),
               init_args: (required_ins.map { |c| "#{c.name}:" } +
                           optional_ins.map { |c| "#{c.name}: nil" }).join(", "))
      end

      sig do
        params(
          table: TableInfo,
          has_many_map: AssocMap,
          has_one_map: AssocMap
        ).returns(String)
      end
      def build_relation(table, has_many_map, has_one_map)
        cls = classify(table.name)
        hm = build_has_many_assocs(table, has_many_map) + build_custom_has_many(table, @custom_associations)
        ho = build_has_one_assocs(table, has_one_map) + build_custom_has_one(table, @custom_associations)
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
               model_class_name: cls,
               record_class_name: "#{cls}Record",
               relation_class_name: qualify("#{cls}Relation"),
               schema_module: qualify("#{cls}Schema"))
      end

      sig { returns(String) }
      def build_manifest
        render("manifest",
               table_names: @tables.keys.map { |n| singularize(n) },
               internal_names: @internal_tables.to_set { |n| singularize(n) },
               enum_entries: enum_manifest_entries(collect_enum_types),
               schema_fingerprint: @schema_fingerprint)
      end

      sig { returns(String) }
      def indent
        @module_name ? "  " : ""
      end

      sig { params(cols: T::Array[ColumnInfo]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_insert_all_columns(cols)
        cols.map do |c|
          { name: c.name, bind_expr: insert_all_bind_expr(c) }
        end
      end

      sig { params(col: ColumnInfo).returns(String) }
      def insert_all_bind_expr(col)
        if col.enum_values
          "rec.#{col.name}.serialize"
        elsif col.nullable
          "((_hv = rec.#{col.name}).nil? ? nil : adapter.encode(#{hakumi_type_for(col).bind_class}.new(_hv)))"
        else
          "adapter.encode(#{hakumi_type_for(col).bind_class}.new(rec.#{col.name}))"
        end
      end

      sig { params(col: ColumnInfo).returns(HakumiType) }
      def hakumi_type_for(col)
        TypeMap.hakumi_type(@dialect.name, col.data_type, col.udt_name)
      end

      sig { void }
      def inject_user_enums!
        @user_enums.each do |table_name, defs|
          table = @tables[table_name]
          next unless table

          defs.each do |enum_def|
            idx = table.columns.index { |c| c.name == enum_def.column_name }
            next unless idx

            old = table.columns[idx]
            next unless old

            validate_enum_column!(table_name, enum_def, old)

            udt = "#{singularize(table_name)}_#{enum_def.column_name}"
            @integer_backed_enums.add(udt)
            table.columns[idx] = ColumnInfo.new(
              name: old.name, data_type: old.data_type, udt_name: udt,
              nullable: old.nullable, default: old.default, max_length: old.max_length,
              enum_values: enum_def.serialized_values
            )
          end
        end
      end

      sig { params(table_name: String, enum_def: EnumDefinition, col: ColumnInfo).void }
      def validate_enum_column!(table_name, enum_def, col)
        col_type = hakumi_type_for(col)
        col_name = enum_def.column_name

        return if col_type == ENUM_COLUMN_TYPE

        raise HakumiORM::Error,
              "Enum :#{col_name} on '#{table_name}': column type '#{col.data_type}' " \
              "(#{col_type.serialize}) is not compatible with user-defined enums. " \
              "User-defined enums require an integer column (sym: int)."
      end

      sig { void }
      def normalize_column_order!
        @tables.each_value do |table|
          table.columns.sort_by!(&:name)
          table.foreign_keys.sort_by!(&:column_name)
          table.unique_columns.sort!
        end
      end

      sig { params(col: ColumnInfo, force_non_nullable: T::Boolean).returns(String) }
      def ruby_type(col, force_non_nullable: false)
        nullable = force_non_nullable ? false : col.nullable
        ev = col.enum_values
        if ev
          base = qualify(enum_class_name(col.udt_name))
          nullable ? "T.nilable(#{base})" : base
        else
          hakumi_type_for(col).ruby_type_string(nullable: nullable)
        end
      end

      sig { params(table: TableInfo, col: ColumnInfo).returns(String) }
      def record_ruby_type(table, col)
        pk_non_nullable = table.primary_key == col.name
        ruby_type(col, force_non_nullable: pk_non_nullable)
      end

      sig { params(table: TableInfo).returns(T::Array[ColumnInfo]) }
      def insertable_columns(table)
        table.columns.reject do |c|
          d = c.default
          (d&.start_with?("nextval(") || d == "auto_increment") || false
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
        HakumiORM.singularize(word)
      end
    end
  end
end
