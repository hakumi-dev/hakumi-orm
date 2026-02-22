# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { returns(T::Hash[String, T::Array[T::Hash[Symbol, String]]]) }
      def compute_has_many_through
        reverse_fks = build_reverse_fk_index

        result = T.let({}, T::Hash[String, T::Array[T::Hash[Symbol, String]]])
        @tables.each_value do |source|
          throughs = compute_throughs_for(source, reverse_fks)
          result[source.name] = throughs unless throughs.empty?
        end
        result
      end

      sig { returns(T::Hash[String, T::Array[T::Hash[Symbol, String]]]) }
      def build_reverse_fk_index
        idx = T.let({}, T::Hash[String, T::Array[T::Hash[Symbol, String]]])
        @tables.each_value do |table|
          table.foreign_keys.each do |fk|
            (idx[fk.foreign_table] ||= []) << { source_table: table.name, fk_column: fk.column_name }
          end
        end
        idx
      end

      sig do
        params(
          source: TableInfo,
          reverse_fks: T::Hash[String, T::Array[T::Hash[Symbol, String]]]
        ).returns(T::Array[T::Hash[Symbol, String]])
      end
      def compute_throughs_for(source, reverse_fks)
        throughs = T.let([], T::Array[T::Hash[Symbol, String]])
        intermediates = reverse_fks[source.name] || []

        intermediates.each do |int_info|
          int_table = @tables[int_info.fetch(:source_table)]
          next unless int_table

          collect_join_table_throughs(source, int_table, int_info, throughs)
          collect_chain_throughs(source, int_table, int_info, reverse_fks, throughs)
        end
        throughs
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

      sig { params(table: TableInfo, assoc_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_has_many_assocs(table, assoc_map)
        pk_col = table.columns.find { |c| c.name == (table.primary_key || "id") }
        pk_type = pk_col ? hakumi_type_for(pk_col).ruby_type_string(nullable: false) : "Integer"

        (assoc_map[table.name] || []).map do |info|
          target_cls = classify(info.fetch(:source_table))
          src = info.fetch(:source_table)
          fk_c = info.fetch(:fk_column)
          {
            method_name: src,
            relation_class: qualify("#{target_cls}Relation"),
            record_class: qualify("#{target_cls}Record"),
            schema_module: qualify("#{target_cls}Schema"),
            fk_const: fk_c.upcase,
            fk_attr: fk_c,
            pk_attr: table.primary_key || "id",
            pk_ruby_type: pk_type,
            delete_sql: assoc_delete_sql(src, fk_c)
          }
        end
      end

      sig { params(table: TableInfo, assoc_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_has_one_assocs(table, assoc_map)
        pk_col = table.columns.find { |c| c.name == (table.primary_key || "id") }
        pk_type = pk_col ? hakumi_type_for(pk_col).ruby_type_string(nullable: false) : "Integer"

        (assoc_map[table.name] || []).map do |info|
          target_cls = classify(info.fetch(:source_table))
          src = info.fetch(:source_table)
          fk_c = info.fetch(:fk_column)
          {
            method_name: singularize(src),
            relation_class: qualify("#{target_cls}Relation"),
            record_class: qualify("#{target_cls}Record"),
            schema_module: qualify("#{target_cls}Schema"),
            fk_const: fk_c.upcase,
            fk_attr: fk_c,
            pk_attr: table.primary_key || "id",
            pk_ruby_type: pk_type,
            delete_sql: assoc_delete_sql(src, fk_c)
          }
        end
      end

      sig { params(table_name: String, fk_column: String).returns(String) }
      def assoc_delete_sql(table_name, fk_column)
        "DELETE FROM #{@dialect.quote_id(table_name)} WHERE #{@dialect.qualified_name(table_name, fk_column)} = #{@dialect.bind_marker(0)}"
      end

      sig do
        params(
          source: TableInfo,
          int_table: TableInfo,
          int_info: T::Hash[Symbol, String],
          throughs: T::Array[T::Hash[Symbol, String]]
        ).void
      end
      def collect_join_table_throughs(source, int_table, int_info, throughs)
        int_table.foreign_keys.each do |fk|
          next if fk.foreign_table == source.name

          target_table = @tables[fk.foreign_table]
          next unless target_table

          throughs << {
            method_name: fk.foreign_table,
            join_table: int_table.name,
            join_fk_to_source: int_info.fetch(:fk_column),
            join_select_field: fk.column_name,
            target_table: fk.foreign_table,
            target_match_field: target_table.primary_key || "id",
            pk_attr: source.primary_key || "id"
          }
        end
      end

      sig do
        params(
          source: TableInfo,
          int_table: TableInfo,
          int_info: T::Hash[Symbol, String],
          reverse_fks: T::Hash[String, T::Array[T::Hash[Symbol, String]]],
          throughs: T::Array[T::Hash[Symbol, String]]
        ).void
      end
      def collect_chain_throughs(source, int_table, int_info, reverse_fks, throughs)
        chain_targets = reverse_fks[int_table.name] || []
        chain_targets.each do |chain_info|
          next if chain_info.fetch(:source_table) == source.name

          target_table = @tables[chain_info.fetch(:source_table)]
          next unless target_table

          throughs << {
            method_name: chain_info.fetch(:source_table),
            join_table: int_table.name,
            join_fk_to_source: int_info.fetch(:fk_column),
            join_select_field: int_table.primary_key || "id",
            target_table: chain_info.fetch(:source_table),
            target_match_field: chain_info.fetch(:fk_column),
            pk_attr: source.primary_key || "id"
          }
        end
      end

      sig { params(table: TableInfo, through_map: T::Hash[String, T::Array[T::Hash[Symbol, String]]]).returns(T::Array[T::Hash[Symbol, String]]) }
      def build_has_many_through_assocs(table, through_map)
        (through_map[table.name] || []).map do |info|
          join_cls = classify(info.fetch(:join_table))
          target_cls = classify(info.fetch(:target_table))
          {
            method_name: info.fetch(:method_name),
            join_relation: qualify("#{join_cls}Relation"),
            join_schema: qualify("#{join_cls}Schema"),
            join_fk_const: info.fetch(:join_fk_to_source).upcase,
            join_select_const: info.fetch(:join_select_field).upcase,
            target_relation: qualify("#{target_cls}Relation"),
            target_schema: qualify("#{target_cls}Schema"),
            target_match_const: info.fetch(:target_match_field).upcase,
            target_record: qualify("#{target_cls}Record"),
            pk_attr: info.fetch(:pk_attr)
          }
        end
      end
    end
  end
end
