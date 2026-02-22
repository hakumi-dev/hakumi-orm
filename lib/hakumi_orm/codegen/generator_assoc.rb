# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    AssocEntry = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }
    AssocMap = T.type_alias { T::Hash[String, T::Array[AssocEntry]] }

    class Generator
      private

      sig do
        params(
          models_dir: String,
          has_many_map: AssocMap,
          has_one_map: AssocMap,
          through_map: AssocMap
        ).void
      end
      def annotate_models!(models_dir, has_many_map, has_one_map, through_map)
        @tables.each_value do |table|
          model_path = File.join(models_dir, "#{singularize(table.name)}.rb")
          next unless File.exist?(model_path)

          ctx = ModelAnnotator::Context.new(
            table: table, dialect: @dialect,
            has_many: build_has_many_assocs(table, has_many_map),
            has_one: build_has_one_assocs(table, has_one_map),
            belongs_to: build_belongs_to_assocs(table),
            has_many_through: build_has_many_through_assocs(table, through_map),
            custom_has_many: build_custom_has_many(table, @custom_associations),
            custom_has_one: build_custom_has_one(table, @custom_associations)
          )
          ModelAnnotator.annotate!(model_path, ctx)
        end
      end

      sig { returns(AssocMap) }
      def compute_has_many_through
        reverse_fks = build_reverse_fk_index

        result = T.let({}, AssocMap)
        @tables.each_value do |source|
          throughs = compute_throughs_for(source, reverse_fks)
          result[source.name] = throughs unless throughs.empty?
        end
        result
      end

      sig { returns(AssocMap) }
      def build_reverse_fk_index
        idx = T.let({}, AssocMap)
        @tables.each_value do |table|
          table.foreign_keys.each do |fk|
            (idx[fk.foreign_table] ||= []) << { source_table: table.name, fk_column: fk.column_name }
          end
        end
        idx
      end

      sig { params(source: TableInfo, reverse_fks: AssocMap).returns(T::Array[AssocEntry]) }
      def compute_throughs_for(source, reverse_fks)
        throughs = T.let([], T::Array[AssocEntry])
        intermediates = reverse_fks[source.name] || []

        intermediates.each do |int_info|
          int_table = @tables[str(int_info, :source_table)]
          next unless int_table

          collect_join_table_throughs(source, int_table, int_info, throughs)
          collect_chain_throughs(source, int_table, int_info, reverse_fks, throughs)
        end
        throughs
      end

      sig { params(table: TableInfo).returns(T::Array[BelongsToEntry]) }
      def build_belongs_to_assocs(table)
        assocs = table.foreign_keys.map do |fk|
          build_belongs_to_hash(table, fk)
        end
        assocs.sort_by { |a| a[:method_name].to_s }
      end

      sig { params(table: TableInfo, foreign_key: ForeignKeyInfo).returns(BelongsToEntry) }
      def build_belongs_to_hash(table, foreign_key)
        fk_col = table.columns.find { |c| c.name == foreign_key.column_name }
        target_cls = classify(foreign_key.foreign_table)
        target_table = @tables[foreign_key.foreign_table]
        target_pk = target_table&.primary_key || "id"
        target_pk_col = target_table&.columns&.find { |c| c.name == target_pk }
        target_pk_type = target_pk_col ? hakumi_type_for(target_pk_col).ruby_type_string(nullable: false) : "Integer"
        {
          method_name: singularize(foreign_key.foreign_table),
          record_class: qualify("#{target_cls}Record"),
          target_relation: qualify("#{target_cls}Relation"),
          target_schema: qualify("#{target_cls}Schema"),
          target_pk_const: target_pk.upcase,
          target_pk_attr: target_pk,
          target_pk_type: target_pk_type,
          fk_attr: foreign_key.column_name,
          nullable: fk_col&.nullable || false
        }
      end

      sig { params(table: TableInfo, assoc_map: AssocMap).returns(T::Array[AssocEntry]) }
      def build_has_many_assocs(table, assoc_map)
        pk_type = pk_type_for(table)
        pk_attr = table.primary_key || "id"
        assocs = (assoc_map[table.name] || []).map do |info|
          src = str(info, :source_table)
          fk_c = str(info, :fk_column)
          build_fk_assoc_entry(src, src, fk_c, pk_attr, pk_type)
        end
        assocs.sort_by { |a| a[:method_name].to_s }
      end

      sig { params(table: TableInfo, assoc_map: AssocMap).returns(T::Array[AssocEntry]) }
      def build_has_one_assocs(table, assoc_map)
        pk_type = pk_type_for(table)
        pk_attr = table.primary_key || "id"
        assocs = (assoc_map[table.name] || []).map do |info|
          src = str(info, :source_table)
          fk_c = str(info, :fk_column)
          build_fk_assoc_entry(singularize(src), src, fk_c, pk_attr, pk_type)
        end
        assocs.sort_by { |a| a[:method_name].to_s }
      end

      sig { params(table: TableInfo).returns(String) }
      def pk_type_for(table)
        pk_col = table.columns.find { |c| c.name == (table.primary_key || "id") }
        pk_col ? hakumi_type_for(pk_col).ruby_type_string(nullable: false) : "Integer"
      end

      sig do
        params(method_name: String, src: String, fk_c: String, pk_attr: String, pk_type: String)
          .returns(AssocEntry)
      end
      def build_fk_assoc_entry(method_name, src, fk_c, pk_attr, pk_type)
        target_cls = classify(src)
        target_table = @tables[src]
        {
          method_name: method_name,
          relation_class: qualify("#{target_cls}Relation"),
          record_class: qualify("#{target_cls}Record"),
          schema_module: qualify("#{target_cls}Schema"),
          fk_const: fk_c.upcase,
          fk_attr: fk_c,
          pk_attr: pk_attr,
          pk_ruby_type: pk_type,
          delete_sql: assoc_delete_sql(src, fk_c),
          target_has_pk: !target_table&.primary_key.nil?
        }
      end

      sig { params(table_name: String, fk_column: String).returns(String) }
      def assoc_delete_sql(table_name, fk_column)
        "DELETE FROM #{@dialect.quote_id(table_name)} WHERE #{@dialect.qualified_name(table_name, fk_column)} = #{@dialect.bind_marker(0)}"
      end

      sig do
        params(
          source: TableInfo,
          int_table: TableInfo,
          int_info: AssocEntry,
          throughs: T::Array[AssocEntry]
        ).void
      end
      def collect_join_table_throughs(source, int_table, int_info, throughs)
        int_table.foreign_keys.each do |fk|
          next if fk.foreign_table == source.name

          target_table = @tables[fk.foreign_table]
          next unless target_table

          int_fk = str(int_info, :fk_column)
          is_singular = int_table.unique_columns.include?(int_fk) &&
                        int_table.unique_columns.include?(fk.column_name)

          throughs << {
            method_name: is_singular ? singularize(fk.foreign_table) : fk.foreign_table,
            join_table: int_table.name,
            join_fk_to_source: int_fk,
            join_select_field: fk.column_name,
            target_table: fk.foreign_table,
            target_match_field: target_table.primary_key || "id",
            pk_attr: source.primary_key || "id",
            singular: is_singular ? "true" : "false"
          }
        end
      end

      sig do
        params(
          source: TableInfo,
          int_table: TableInfo,
          int_info: AssocEntry,
          reverse_fks: AssocMap,
          throughs: T::Array[AssocEntry]
        ).void
      end
      def collect_chain_throughs(source, int_table, int_info, reverse_fks, throughs)
        chain_targets = reverse_fks[int_table.name] || []
        chain_targets.each do |chain_info|
          build_chain_through(source, int_table, int_info, chain_info, throughs)
        end
      end

      sig do
        params(
          source: TableInfo, int_table: TableInfo,
          int_info: AssocEntry, chain_info: AssocEntry,
          throughs: T::Array[AssocEntry]
        ).void
      end
      def build_chain_through(source, int_table, int_info, chain_info, throughs)
        chain_src = str(chain_info, :source_table)
        chain_fk = str(chain_info, :fk_column)
        return if chain_src == source.name

        target_table = @tables[chain_src]
        return unless target_table

        is_singular = int_table.unique_columns.include?(str(int_info, :fk_column)) &&
                      target_table.unique_columns.include?(chain_fk)

        throughs << {
          method_name: is_singular ? singularize(chain_src) : chain_src,
          join_table: int_table.name,
          join_fk_to_source: str(int_info, :fk_column),
          join_select_field: int_table.primary_key || "id",
          target_table: chain_src,
          target_match_field: chain_fk,
          pk_attr: source.primary_key || "id",
          singular: is_singular ? "true" : "false"
        }
      end

      sig { params(table: TableInfo, through_map: AssocMap).returns(T::Array[AssocEntry]) }
      def build_has_many_through_assocs(table, through_map)
        assocs = (through_map[table.name] || []).map { |info| build_through_entry(info) }
        assocs.sort_by { |a| a[:method_name].to_s }
      end

      sig { params(info: AssocEntry).returns(AssocEntry) }
      def build_through_entry(info)
        join_cls = classify(str(info, :join_table))
        target_cls = classify(str(info, :target_table))
        {
          method_name: str(info, :method_name),
          join_relation: qualify("#{join_cls}Relation"),
          join_schema: qualify("#{join_cls}Schema"),
          join_fk_const: str(info, :join_fk_to_source).upcase,
          join_select_const: str(info, :join_select_field).upcase,
          target_relation: qualify("#{target_cls}Relation"),
          target_schema: qualify("#{target_cls}Schema"),
          target_match_const: str(info, :target_match_field).upcase,
          target_record: qualify("#{target_cls}Record"),
          pk_attr: str(info, :pk_attr),
          singular: info.fetch(:singular, "false").to_s
        }
      end
      sig { params(hash: AssocEntry, key: Symbol).returns(String) }
      def str(hash, key)
        hash.fetch(key).to_s
      end
    end
  end
end
