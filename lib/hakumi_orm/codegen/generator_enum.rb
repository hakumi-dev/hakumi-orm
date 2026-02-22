# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class Generator
      private

      sig { returns(T::Hash[String, T::Array[String]]) }
      def collect_enum_types
        seen = T.let({}, T::Hash[String, T::Array[String]])
        @tables.each_value do |table|
          table.columns.each do |col|
            ev = col.enum_values
            next unless ev

            seen[col.udt_name] ||= ev
          end
        end
        seen
      end

      sig { params(enum_types: T::Hash[String, T::Array[String]]).void }
      def generate_enum_files!(enum_types)
        enum_dir = File.join(@output_dir, "enums")
        FileUtils.mkdir_p(enum_dir)

        enum_types.each do |udt_name, values|
          cls_name = enum_class_name(udt_name)
          code = render("enum",
                        module_name: @module_name,
                        ind: indent,
                        enum_class_name: qualify(cls_name),
                        values: values.map { |v| { const: v.upcase.gsub(/[^A-Z0-9_]/, "_"), serialized: v } })
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
        return { delete_sql: nil, pk_attr: nil, soft_delete: false, soft_delete_sql: nil } unless pk

        has_sd = soft_delete_column?(table)
        tbl = @dialect.quote_id(table.name)
        pk_where = "#{@dialect.qualified_name(table.name, pk)} = #{@dialect.bind_marker(0)}"
        hard_sql = "DELETE FROM #{tbl} WHERE #{pk_where}"
        sd_sql = if has_sd
                   da = @dialect.quote_id("deleted_at")
                   pk_qn = @dialect.qualified_name(table.name, pk)
                   "UPDATE #{tbl} SET #{da} = #{@dialect.bind_marker(0)} WHERE #{pk_qn} = #{@dialect.bind_marker(1)}"
                 end

        { delete_sql: hard_sql, pk_attr: pk, soft_delete: has_sd, soft_delete_sql: sd_sql }
      end

      sig { params(table: TableInfo).returns(T::Boolean) }
      def soft_delete_column?(table)
        @soft_delete_tables.include?(table.name)
      end

      sig { params(table: TableInfo).returns(T::Array[String]) }
      def build_cast_lines(table)
        table.columns.each_with_index.map do |col, ci|
          ev = col.enum_values
          if ev
            enum_cls = qualify(enum_class_name(col.udt_name))
            raw = "c#{ci}[i]"
            if col.nullable
              "((_hv = #{raw}).nil? ? nil : #{enum_cls}.deserialize(_hv))"
            else
              "#{enum_cls}.deserialize(#{raw})"
            end
          else
            TypeMap.cast_expression(hakumi_type_for(col), "c#{ci}[i]", nullable: col.nullable)
          end
        end
      end
    end
  end
end
