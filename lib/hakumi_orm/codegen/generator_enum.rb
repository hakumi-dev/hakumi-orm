# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    EnumValue = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }
    EnumTypeMap = T.type_alias { T::Hash[String, T::Array[EnumValue]] }

    class Generator
      private

      sig { returns(EnumTypeMap) }
      def collect_enum_types
        seen = T.let({}, EnumTypeMap)

        @user_enums.each do |table_name, defs|
          defs.each do |enum_def|
            udt = "#{table_name}_#{enum_def.column_name}"
            seen[udt] = enum_def.values.map do |key, db_val|
              { const: key.to_s.upcase.gsub(/[^A-Z0-9_]/, "_"), serialized: db_val.to_s, integer: true }
            end
          end
        end

        @tables.each_value do |table|
          table.columns.each do |col|
            ev = col.enum_values
            next unless ev
            next if seen.key?(col.udt_name)

            seen[col.udt_name] = ev.map do |v|
              { const: v.upcase.gsub(/[^A-Z0-9_]/, "_"), serialized: v, integer: false }
            end
          end
        end
        seen
      end

      sig { params(enum_types: EnumTypeMap).void }
      def generate_enum_files!(enum_types)
        enum_dir = File.join(@output_dir, "enums")
        FileUtils.mkdir_p(enum_dir)

        enum_types.each do |udt_name, values|
          cls_name = enum_class_name(udt_name)
          code = render("enum",
                        module_name: @module_name,
                        ind: indent,
                        enum_class_name: qualify(cls_name),
                        values: values)
          File.write(File.join(enum_dir, "#{udt_name}.rb"), code)
        end
      end

      sig { params(udt_name: String).returns(String) }
      def enum_class_name(udt_name)
        "#{classify(udt_name)}Enum"
      end

      sig { params(table: TableInfo).returns(T::Hash[Symbol, T.nilable(String)]) }
      def build_delete_locals(table)
        pk = table.primary_key
        return { delete_sql: nil, pk_attr: nil, soft_delete: false, soft_delete_sql: nil, soft_delete_attr: nil } unless pk

        sd_col = soft_delete_column(table)
        tbl = @dialect.quote_id(table.name)
        pk_where = "#{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)}"
        hard_sql = "DELETE FROM #{tbl} WHERE #{pk_where}"
        sd_sql = if sd_col
                   da = @dialect.quote_id(sd_col)
                   pk_qn = @dialect.qualified_name(table.name, pk)
                   "UPDATE #{tbl} SET #{da} = #{@dialect.bind_marker(0)} WHERE #{pk_qn} = #{@dialect.bind_marker(1)}"
                 end

        { delete_sql: hard_sql, pk_attr: pk, soft_delete: !sd_col.nil?, soft_delete_sql: sd_sql, soft_delete_attr: sd_col }
      end

      sig { params(table: TableInfo).returns(T.nilable(String)) }
      def soft_delete_column(table)
        @soft_delete_tables[table.name]
      end

      sig { params(table: TableInfo).returns(T::Array[EnumValue]) }
      def build_enum_predicates(table)
        defs = @user_enums[table.name]
        return [] unless defs

        result = T.let([], T::Array[EnumValue])
        defs.each do |enum_def|
          col = table.columns.find { |c| c.name == enum_def.column_name }
          next unless col

          enum_cls = qualify(enum_class_name(col.udt_name))
          enum_def.values.each_key do |key|
            const_name = key.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")
            method_name = build_predicate_name(key.to_s, enum_def.prefix, enum_def.suffix)
            result << { method_name: method_name, column: enum_def.column_name, enum_class: enum_cls, const: const_name }
          end
        end
        result
      end

      sig { params(key: String, prefix: T.nilable(Symbol), suffix: T.nilable(Symbol)).returns(String) }
      def build_predicate_name(key, prefix, suffix)
        parts = []
        parts << prefix.to_s if prefix
        parts << key
        parts << suffix.to_s if suffix
        "#{parts.join("_")}?"
      end

      sig { params(table: TableInfo).returns(T::Array[String]) }
      def build_cast_lines(table)
        pk = table.primary_key
        table.columns.each_with_index.map do |col, ci|
          nullable = col.name == pk ? false : col.nullable
          ev = col.enum_values
          if ev
            enum_cls = qualify(enum_class_name(col.udt_name))
            raw = "row[#{ci}]"
            int_enum = @integer_backed_enums.include?(col.udt_name)
            coerce = int_enum ? ".to_i" : ""
            if nullable
              "((_hv = #{raw}).nil? ? nil : #{enum_cls}.deserialize(_hv#{coerce}))"
            else
              "#{enum_cls}.deserialize(#{raw}#{coerce})"
            end
          else
            TypeMap.cast_expression(hakumi_type_for(col), "row[#{ci}]", nullable: nullable)
          end
        end
      end
    end
  end
end
