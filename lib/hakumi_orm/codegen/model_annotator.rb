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

      sig { params(lines: T::Array[String], table: TableInfo, dialect: Dialect::Base).void }
      def self.append_header(lines, table, dialect)
        lines << "# Table: #{table.name}"
        pk = table.primary_key
        return unless pk

        pk_col = table.columns.find { |c| c.name == pk }
        pk_type = pk_col ? TypeMap.hakumi_type(dialect.name, pk_col.data_type, pk_col.udt_name).serialize : "unknown"
        lines << "# Primary key: #{pk} (#{pk_type}, not null)"
      end

      sig { params(lines: T::Array[String], table: TableInfo, dialect: Dialect::Base).void }
      def self.append_columns(lines, table, dialect)
        lines << "#"
        lines << "# Columns:"
        table.columns.each do |col|
          ht = TypeMap.hakumi_type(dialect.name, col.data_type, col.udt_name)
          constraints = col.nullable ? "nullable" : "not null"
          d = col.default
          constraints = "#{constraints}, default: #{d}" if d
          constraints = "#{constraints}, PK" if col.name == table.primary_key
          lines << "#   #{col.name.ljust(16)} #{ht.serialize.ljust(12)} #{constraints}"
        end
      end

      sig { params(lines: T::Array[String], ctx: Context).void }
      def self.append_associations(lines, ctx)
        assoc_lines = T.let([], T::Array[String])
        table_name = ctx.table.name

        append_fk_has_many_lines(assoc_lines, ctx.has_many, table_name)
        append_fk_has_one_lines(assoc_lines, ctx.has_one, table_name)
        append_belongs_to_lines(assoc_lines, ctx.belongs_to, table_name)
        append_through_lines(assoc_lines, ctx.has_many_through)
        append_custom_assoc_lines(assoc_lines, ctx.custom_has_many, "has_many", table_name)
        append_custom_assoc_lines(assoc_lines, ctx.custom_has_one, "has_one", table_name)

        return if assoc_lines.empty?

        lines << "#"
        lines << "# Associations:"
        lines.concat(assoc_lines)
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash], table_name: String).void }
      def self.append_fk_has_many_lines(out, assocs, table_name)
        assocs.each do |a|
          out << assoc_line("has_many", a[:method_name].to_s,
                            "FK: #{a[:method_name]}.#{a[:fk_attr]} -> #{table_name}.#{a[:pk_attr]}")
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash], table_name: String).void }
      def self.append_fk_has_one_lines(out, assocs, table_name)
        assocs.each do |a|
          out << assoc_line("has_one", a[:method_name].to_s,
                            "FK: #{a[:method_name]}.#{a[:fk_attr]} -> #{table_name}.#{a[:pk_attr]}")
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[BelongsToEntry], table_name: String).void }
      def self.append_belongs_to_lines(out, assocs, table_name)
        assocs.each do |a|
          out << assoc_line("belongs_to", a[:method_name].to_s,
                            "FK: #{table_name}.#{a[:fk_attr]} -> #{a[:method_name]}.#{a[:target_pk_attr]}")
        end
      end

      sig { params(out: T::Array[String], assocs: T::Array[AssocHash]).void }
      def self.append_through_lines(out, assocs)
        assocs.each do |a|
          out << assoc_line("has_many", a[:method_name].to_s, "through: #{a[:join_table]}")
        end
      end

      sig do
        params(
          out: T::Array[String],
          assocs: T::Array[AssocHash],
          kind: String,
          source_table: String
        ).void
      end
      def self.append_custom_assoc_lines(out, assocs, kind, source_table)
        assocs.each do |a|
          target = a[:target_table] || a[:method_name]
          ob = a[:order_by_const]&.to_s
          detail = "custom: #{target}.#{a[:fk_attr]} -> #{source_table}.#{a[:pk_attr]}"
          detail = "#{detail}, order: #{ob.downcase}" if ob
          out << assoc_line(kind, a[:method_name].to_s, detail)
        end
      end

      sig { params(kind: String, name: String, detail: String).returns(String) }
      def self.assoc_line(kind, name, detail)
        "#   #{kind.ljust(12)} :#{name.ljust(21)} (#{detail})"
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
