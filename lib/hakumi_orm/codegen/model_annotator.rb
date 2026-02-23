# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class ModelAnnotator
      extend T::Sig

      MARKER_START = "# == Schema Information =="
      MARKER_END = "# == End Schema Information =="
      MARKER_START_RE = T.let(/^# == Schema Information ==\s*$/, Regexp)
      MARKER_END_RE = T.let(/^# == End Schema Information ==\s*$/, Regexp)

      AssocHash = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }

      class Context < T::Struct
        const :table, TableInfo
        const :dialect, Dialect::Base
        const :has_many, T::Array[AssocHash]
        const :has_one, T::Array[AssocHash]
        const :belongs_to, T::Array[BelongsToEntry]
        const :has_many_through, T::Array[AssocHash]
        const :custom_has_many, T::Array[AssocHash]
        const :custom_has_one, T::Array[AssocHash]
        const :enum_predicates, T::Array[EnumValue], default: []
      end

      sig { params(model_path: String, ctx: Context).void }
      def self.annotate!(model_path, ctx)
        block = build_annotation(ctx)
        content = File.read(model_path)
        updated = insert_annotation(content, block)
        File.write(model_path, updated)
      end

      sig { params(ctx: Context).returns(String) }
      def self.build_annotation(ctx)
        lines = T.let([MARKER_START, "#"], T::Array[String])
        table = ctx.table

        append_header(lines, table, ctx.dialect)
        append_columns(lines, table, ctx.dialect)
        append_enums(lines, ctx.enum_predicates)
        append_associations(lines, ctx)

        lines << "#"
        lines << MARKER_END
        lines.join("\n")
      end

      sig { params(content: String, annotation: String).returns(String) }
      def self.insert_annotation(content, annotation)
        lines = content.lines
        start_idx = lines.index { |l| l.match?(MARKER_START_RE) }
        end_idx = lines.index { |l| l.match?(MARKER_END_RE) }

        if start_idx && end_idx && end_idx > start_idx
          before = (lines[0...start_idx] || []).map(&:chomp)
          after = (lines[(end_idx + 1)..] || []).map(&:chomp)
          "#{(before + [annotation] + after).join("\n")}\n"
        else
          insert_before_class(lines, annotation)
        end
      end

      sig { params(lines: T::Array[String], annotation: String).returns(String) }
      def self.insert_before_class(lines, annotation)
        class_idx = lines.index { |l| l.match?(/^\s*class\s/) }

        if class_idx
          before = (lines[0...class_idx] || []).map(&:chomp)
          after = (lines[class_idx..] || []).map(&:chomp)
          "#{(before + [annotation, ""] + after).join("\n")}\n"
        else
          "#{annotation}\n\n#{lines.map(&:chomp).join("\n")}\n"
        end
      end

      BARE_TYPE_ALLOWANCE = 16

      sig { params(lines: T::Array[String], table: TableInfo, dialect: Dialect::Base).void }
      def self.append_header(lines, table, dialect)
        lines << "# Table name: #{table.name}"
        pk = table.primary_key
        return unless pk

        pk_col = table.columns.find { |c| c.name == pk }
        pk_type = pk_col ? TypeMap.hakumi_type(dialect.name, pk_col.data_type, pk_col.udt_name).serialize : "unknown"
        lines << "# Primary key: #{pk} (#{pk_type}, not null)"
      end

      sig { params(lines: T::Array[String], table: TableInfo, dialect: Dialect::Base).void }
      def self.append_columns(lines, table, dialect)
        lines << "#"
        max_name = (table.columns.map { |c| c.name.length }.max || 0) + 1
        col_meta = table.columns.map { |col| [col, col_type_label(col, dialect), col_attrs(col, table)] }
        max_attrs = col_meta.map { |_, _, a| a.length }.max || 0

        col_meta.each do |col, type_label, attrs|
          lines << "# #{col.name.ljust(max_name)}:#{type_label.ljust(BARE_TYPE_ALLOWANCE)} #{attrs.ljust(max_attrs)}".rstrip
        end
      end

      sig { params(col: ColumnInfo, dialect: Dialect::Base).returns(String) }
      def self.col_type_label(col, dialect)
        ev = col.enum_values
        if ev
          "enum(#{classify_udt(col.udt_name)})"
        else
          TypeMap.hakumi_type(dialect.name, col.data_type, col.udt_name).serialize
        end
      end

      sig { params(col: ColumnInfo, table: TableInfo).returns(String) }
      def self.col_attrs(col, table)
        parts = []
        parts << "not null" unless col.nullable
        parts << "default(#{col.default})" if col.default
        parts << "primary key" if col.name == table.primary_key
        parts.join(", ")
      end

      sig { params(udt_name: String).returns(String) }
      def self.classify_udt(udt_name)
        "#{udt_name.split("_").map(&:capitalize).join}Enum"
      end

      sig { params(lines: T::Array[String], predicates: T::Array[EnumValue]).void }
      def self.append_enums(lines, predicates)
        return if predicates.empty?

        grouped = group_predicates(predicates)
        lines << "#"
        lines << "# Enums:"
        max_col = (grouped.keys.map(&:length).max || 0) + 1
        grouped.each { |col, preds| append_enum_group(lines, col, preds, max_col) }
      end

      sig { params(predicates: T::Array[EnumValue]).returns(T::Hash[String, T::Array[EnumValue]]) }
      def self.group_predicates(predicates)
        grouped = T.let({}, T::Hash[String, T::Array[EnumValue]])
        predicates.each { |pred| (grouped[str(pred, :column)] ||= []) << pred }
        grouped
      end

      sig { params(lines: T::Array[String], col: String, preds: T::Array[EnumValue], max_col: Integer).void }
      def self.append_enum_group(lines, col, preds, max_col)
        first_pred = preds.first
        return unless first_pred

        enum_cls = str(first_pred, :enum_class)
        values = preds.map { |p| str(p, :const).downcase }.join(", ")
        methods = preds.map { |p| str(p, :method_name) }.join(", ")
        lines << "# #{col.ljust(max_col)}:#{enum_cls} [#{values}]".rstrip
        lines << "# #{" ".ljust(max_col + 1)} predicates: #{methods}".rstrip
      end

      sig { params(hash: EnumValue, key: Symbol).returns(String) }
      def self.str(hash, key)
        T.cast(hash.fetch(key), String)
      end

      sig { params(lines: T::Array[String], ctx: Context).void }
      def self.append_associations(lines, ctx)
        entries = collect_assoc_entries(ctx)
        return if entries.empty?

        max_kind = (entries.map { |e| e[0].length }.max || 0) + 1
        max_name = (entries.map { |e| e[1].length }.max || 0) + 1

        lines << "#"
        lines << "# Associations:"
        entries.each do |kind, name, detail|
          lines << "# #{kind.ljust(max_kind)}:#{name.ljust(max_name)} #{detail}".rstrip
        end
      end

      AssocEntry = T.type_alias { [String, String, String] }

      sig { params(ctx: Context).returns(T::Array[AssocEntry]) }
      def self.collect_assoc_entries(ctx)
        entries = T.let([], T::Array[AssocEntry])
        tn = ctx.table.name

        append_fk_entries(entries, "has_many", ctx.has_many, tn)
        append_fk_entries(entries, "has_one", ctx.has_one, tn)
        append_belongs_to_entries(entries, ctx.belongs_to, tn)
        append_through_entries(entries, ctx.has_many_through)
        ctx.custom_has_many.each { |a| entries << custom_assoc_entry("has_many", a, tn) }
        ctx.custom_has_one.each { |a| entries << custom_assoc_entry("has_one", a, tn) }
        entries
      end

      sig { params(entries: T::Array[AssocEntry], kind: String, assocs: T::Array[AssocHash], table_name: String).void }
      def self.append_fk_entries(entries, kind, assocs, table_name)
        assocs.each do |a|
          entries << [kind, a[:method_name].to_s, "FK: #{a[:method_name]}.#{a[:fk_attr]} -> #{table_name}.#{a[:pk_attr]}"]
        end
      end

      sig { params(entries: T::Array[AssocEntry], assocs: T::Array[BelongsToEntry], table_name: String).void }
      def self.append_belongs_to_entries(entries, assocs, table_name)
        assocs.each do |a|
          entries << ["belongs_to", a[:method_name].to_s, "FK: #{table_name}.#{a[:fk_attr]} -> #{a[:method_name]}.#{a[:target_pk_attr]}"]
        end
      end

      sig { params(entries: T::Array[AssocEntry], assocs: T::Array[AssocHash]).void }
      def self.append_through_entries(entries, assocs)
        assocs.each do |a|
          entries << ["has_many", a[:method_name].to_s, "through: #{a[:join_table]}"]
        end
      end

      sig { params(kind: String, a: AssocHash, source_table: String).returns(AssocEntry) }
      def self.custom_assoc_entry(kind, a, source_table)
        target = a[:target_table] || a[:method_name]
        ob = a[:order_by_const]&.to_s
        detail = "custom: #{target}.#{a[:fk_attr]} -> #{source_table}.#{a[:pk_attr]}"
        detail = "#{detail}, order: #{ob.downcase}" if ob
        [kind, a[:method_name].to_s, detail]
      end

      sig do
        params(
          generator: Generator,
          table: TableInfo,
          custom_assocs: T::Hash[String, T::Array[CustomAssociation]]
        ).returns(Context)
      end
      def self.build_cli_context(generator, table, custom_assocs)
        hm_map = generator.send(:compute_has_many)
        ho_map = generator.send(:compute_has_one)
        through_map = generator.send(:compute_has_many_through)

        Context.new(
          table: table,
          dialect: generator.instance_variable_get(:@dialect),
          has_many: generator.send(:build_has_many_assocs, table, hm_map),
          has_one: generator.send(:build_has_one_assocs, table, ho_map),
          belongs_to: generator.send(:build_belongs_to_assocs, table),
          has_many_through: generator.send(:build_has_many_through_assocs, table, through_map),
          custom_has_many: generator.send(:build_custom_has_many, table, custom_assocs),
          custom_has_one: generator.send(:build_custom_has_one, table, custom_assocs),
          enum_predicates: generator.send(:build_enum_predicates, table)
        )
      end

      sig { params(ctx: Context).returns(T::Array[String]) }
      def self.build_assoc_lines_for_cli(ctx)
        lines = T.let([], T::Array[String])
        tn = ctx.table.name

        append_cli_fk(lines, ctx.has_many, "has_many", tn)
        append_cli_fk(lines, ctx.has_one, "has_one", tn)
        append_cli_belongs_to(lines, ctx.belongs_to, tn)
        append_cli_through(lines, ctx.has_many_through)
        append_cli_custom(lines, ctx.custom_has_many, "has_many", tn)
        append_cli_custom(lines, ctx.custom_has_one, "has_one", tn)

        lines
      end

      sig { params(out: T::Array[String], assocs: T::Array[BelongsToEntry], table_name: String).void }
      def self.append_cli_belongs_to(out, assocs, table_name)
        assocs.each do |a|
          mapping = "#{table_name}.#{a[:fk_attr]} -> #{a[:method_name]}.#{a[:target_pk_attr]}"
          out << "  #{"FK".ljust(8)}#{"belongs_to".ljust(12)}:#{a[:method_name].to_s.ljust(22)} #{mapping}"
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash]).void }
      def self.append_cli_through(out, assocs)
        assocs.each do |a|
          out << "  #{"through".ljust(8)}#{"has_many".ljust(12)}:#{a[:method_name].to_s.ljust(22)} via #{a[:join_table]}"
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash], kind: String, table_name: String).void }
      def self.append_cli_fk(out, assocs, kind, table_name)
        assocs.each do |a|
          mapping = "#{a[:method_name]}.#{a[:fk_attr]} -> #{table_name}.#{a[:pk_attr]}"
          out << "  #{"FK".ljust(8)}#{kind.ljust(12)}:#{a[:method_name].to_s.ljust(22)} #{mapping}"
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash], kind: String, table_name: String).void }
      def self.append_cli_custom(out, assocs, kind, table_name)
        assocs.each do |a|
          mapping = "#{a[:target_table]}.#{a[:fk_attr]} -> #{table_name}.#{a[:pk_attr]}"
          out << "  #{"custom".ljust(8)}#{kind.ljust(12)}:#{a[:method_name].to_s.ljust(22)} #{mapping}"
        end
      end
    end
  end
end
