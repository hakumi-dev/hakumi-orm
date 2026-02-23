# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { params(has_many_map: AssocMap, has_one_map: AssocMap).returns(T::Hash[String, T::Array[String]]) }
      def build_fk_assoc_names(has_many_map, has_one_map)
        result = T.let({}, T::Hash[String, T::Array[String]])
        has_many_map.each do |table_name, assocs|
          (result[table_name] ||= []).concat(assocs.map { |a| a.fetch(:source_table).to_s })
        end
        has_one_map.each do |table_name, assocs|
          (result[table_name] ||= []).concat(assocs.map { |a| singularize(a.fetch(:source_table).to_s) })
        end
        result
      end

      sig { params(custom_assocs: T::Hash[String, T::Array[CustomAssociation]], fk_names: T::Hash[String, T::Array[String]]).void }
      def validate_custom_assocs!(custom_assocs, fk_names)
        custom_assocs.each do |source_table_name, assocs|
          source = @tables[source_table_name]
          raise HakumiORM::Error, "Custom association source table '#{source_table_name}' does not exist" unless source

          assocs.each { |a| validate_single_assoc!(a, source, fk_names[source_table_name] || []) }
        end
      end

      sig { params(a: CustomAssociation, source: TableInfo, existing_fk_names: T::Array[String]).void }
      def validate_single_assoc!(a, source, existing_fk_names)
        validate_assoc_basics!(a)

        target = @tables[a.target_table]
        raise HakumiORM::Error, "Custom association '#{a.name}': target table '#{a.target_table}' does not exist" unless target

        pk_col = find_assoc_column!(a, source, :primary_key)
        fk_col = find_assoc_column!(a, target, :foreign_key)

        if pk_col.nullable
          raise HakumiORM::Error,
                "Custom association '#{a.name}': source column '#{a.primary_key}' is nullable " \
                "(custom associations require non-null source column)"
        end

        validate_type_compat!(a, pk_col, fk_col)
        validate_no_collision!(a, source, existing_fk_names)
      end

      sig { params(a: CustomAssociation).void }
      def validate_assoc_basics!(a)
        unless CustomAssociation::VALID_KINDS.include?(a.kind)
          raise HakumiORM::Error, "Custom association '#{a.name}': kind must be :has_many or :has_one, got :#{a.kind}"
        end

        return if CustomAssociation::VALID_NAME_PATTERN.match?(a.name)

        raise HakumiORM::Error,
              "Custom association '#{a.name}': name must match #{CustomAssociation::VALID_NAME_PATTERN.inspect}"
      end

      sig { params(a: CustomAssociation, table: TableInfo, role: Symbol).returns(ColumnInfo) }
      def find_assoc_column!(a, table, role)
        col_name = role == :primary_key ? a.primary_key : a.foreign_key
        col = table.columns.find { |c| c.name == col_name }
        return col if col

        raise HakumiORM::Error,
              "Custom association '#{a.name}': #{role} '#{col_name}' not found on '#{table.name}'"
      end

      sig { params(a: CustomAssociation, pk_col: ColumnInfo, fk_col: ColumnInfo).void }
      def validate_type_compat!(a, pk_col, fk_col)
        pk_type = hakumi_type_for(pk_col)
        fk_type = hakumi_type_for(fk_col)
        return if pk_type.compatible_with?(fk_type)

        raise HakumiORM::Error,
              "Custom association '#{a.name}': type mismatch between " \
              "'#{a.primary_key}' (#{pk_type.serialize}) and '#{a.foreign_key}' (#{fk_type.serialize})"
      end

      sig { params(a: CustomAssociation, source: TableInfo, existing_fk_names: T::Array[String]).void }
      def validate_no_collision!(a, source, existing_fk_names)
        if existing_fk_names.include?(a.name)
          raise HakumiORM::Error,
                "Custom association '#{a.name}' on '#{source.name}': name collision with existing FK association"
        end

        return unless source.columns.any? { |c| c.name == a.name }

        raise HakumiORM::Error,
              "Custom association '#{a.name}' on '#{source.name}': name collision with existing column"
      end

      sig do
        params(
          table: TableInfo,
          custom_assocs: T::Hash[String, T::Array[CustomAssociation]]
        ).returns(T::Array[AssocEntry])
      end
      def build_custom_has_many(table, custom_assocs)
        (custom_assocs[table.name] || []).select { |a| a.kind == :has_many }.map do |a|
          build_custom_assoc_hash(table, a)
        end
      end

      sig do
        params(
          table: TableInfo,
          custom_assocs: T::Hash[String, T::Array[CustomAssociation]]
        ).returns(T::Array[AssocEntry])
      end
      def build_custom_has_one(table, custom_assocs)
        (custom_assocs[table.name] || []).select { |a| a.kind == :has_one }.map do |a|
          build_custom_assoc_hash(table, a)
        end
      end

      sig { params(table: TableInfo, a: CustomAssociation).returns(AssocEntry) }
      def build_custom_assoc_hash(table, a)
        result = build_custom_assoc_base(table, a)
        ob = a.order_by
        result[:order_by_const] = ob.upcase if ob
        sc = a.scope
        result[:scope_expr] = sc if sc
        result
      end

      sig { params(table: TableInfo, a: CustomAssociation).returns(AssocEntry) }
      def build_custom_assoc_base(table, a)
        target_cls = classify(a.target_table)
        target_table = @tables[a.target_table]
        pk_col = table.columns.find { |c| c.name == a.primary_key }
        pk_type = pk_col ? hakumi_type_for(pk_col).ruby_type_string(nullable: false) : "String"
        {
          method_name: a.name,
          target_table: a.target_table,
          relation_class: qualify("#{target_cls}Relation"),
          record_class: qualify("#{target_cls}Record"),
          schema_module: qualify("#{target_cls}Schema"),
          fk_const: a.foreign_key.upcase,
          fk_attr: a.foreign_key,
          pk_attr: a.primary_key,
          pk_ruby_type: pk_type,
          delete_sql: assoc_delete_sql(a.target_table, a.foreign_key),
          target_has_pk: !target_table&.primary_key.nil?
        }
      end
    end
  end
end
