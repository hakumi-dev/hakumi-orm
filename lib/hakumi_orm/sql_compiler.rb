# typed: strict
# frozen_string_literal: true

# Internal component for sql_compiler.
module HakumiORM
  # Internal class for HakumiORM.
  class SqlCompiler
    extend T::Sig
    CteEntry = T.type_alias { [String, CompiledQuery, T::Boolean] }

    JOIN_KEYWORDS = T.let({
      inner: " INNER JOIN ",
      left: " LEFT JOIN ",
      right: " RIGHT JOIN ",
      cross: " CROSS JOIN "
    }.freeze, T::Hash[Symbol, String])

    SQL_QUOTED_OR_BIND_MARKER = T.let(
      %r{'(?:''|[^'])*'|"(?:""|[^"])*"|--[^\n]*|/\*(?:[^*]|\*(?!/))*\*/|\$\d+},
      Regexp
    )

    sig { params(dialect: Dialect::Base).void }
    def initialize(dialect)
      @dialect = T.let(dialect, Dialect::Base)
    end

    sig do
      params(
        table: String,
        columns: T::Array[FieldRef],
        table_alias: T.nilable(String),
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr),
        orders: T::Array[OrderClause],
        joins: T::Array[JoinClause],
        limit_val: T.nilable(Integer),
        offset_val: T.nilable(Integer),
        distinct: T::Boolean,
        lock: T.nilable(String),
        group_fields: T::Array[FieldRef],
        having_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def select(table:, columns:, table_alias: nil, ctes: [], where_expr: nil, orders: [], joins: [], limit_val: nil, offset_val: nil,
               distinct: false, lock: nil, group_fields: [], having_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << (distinct ? "SELECT DISTINCT " : "SELECT ")
      columns.each_with_index do |col, i|
        buf << ", " if i.positive?
        buf << qualify(col)
      end

      buf << " FROM "
      append_table_reference(buf, table, table_alias)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << qualify(j.source_field)
        buf << " = "
        buf << qualify(j.target_field)
      end

      if where_expr
        buf << " WHERE "
        idx = compile_expr(where_expr, buf, binds, idx)
      end

      unless group_fields.empty?
        buf << " GROUP BY "
        group_fields.each_with_index do |f, i|
          buf << ", " if i.positive?
          buf << qualify(f)
        end
      end

      if having_expr
        buf << " HAVING "
        compile_expr(having_expr, buf, binds, idx)
      end

      unless orders.empty?
        buf << " ORDER BY "
        orders.each_with_index do |o, i|
          buf << ", " if i.positive?
          buf << qualify(o.field)
          buf << (o.direction == :desc ? " DESC" : " ASC")
        end
      end

      buf << " LIMIT " << limit_val.to_s if limit_val
      buf << " OFFSET " << offset_val.to_s if offset_val
      buf << " " << lock if lock

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        function: String,
        field: FieldRef,
        table_alias: T.nilable(String),
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def aggregate(table:, function:, field:, table_alias: nil, ctes: [], where_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT " << function << "(" << qualify(field) << ") FROM "
      append_table_reference(buf, table, table_alias)

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr),
        joins: T::Array[JoinClause],
        table_alias: T.nilable(String)
      ).returns(CompiledQuery)
    end
    def count(table:, ctes: [], where_expr: nil, joins: [], table_alias: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT COUNT(*) FROM "
      append_table_reference(buf, table, table_alias)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << qualify(j.source_field)
        buf << " = "
        buf << qualify(j.target_field)
      end

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr),
        joins: T::Array[JoinClause],
        table_alias: T.nilable(String)
      ).returns(CompiledQuery)
    end
    def exists(table:, ctes: [], where_expr: nil, joins: [], table_alias: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT 1 FROM "
      append_table_reference(buf, table, table_alias)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << qualify(j.source_field)
        buf << " = "
        buf << qualify(j.target_field)
      end

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      buf << " LIMIT 1"

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr),
        table_alias: T.nilable(String)
      ).returns(CompiledQuery)
    end
    def delete(table:, ctes: [], where_expr: nil, table_alias: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "DELETE FROM "
      append_table_reference(buf, table, table_alias)

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        assignments: T::Array[Assignment],
        ctes: T::Array[CteEntry],
        where_expr: T.nilable(Expr),
        table_alias: T.nilable(String)
      ).returns(CompiledQuery)
    end
    def update(table:, assignments:, ctes: [], where_expr: nil, table_alias: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << "UPDATE "
      append_table_reference(buf, table, table_alias)
      buf << " SET "

      assignments.each_with_index do |a, i|
        buf << ", " if i.positive?
        buf << @dialect.quote_id(a.field.column_name)
        buf << " = "
        buf << @dialect.bind_marker(idx)
        binds << a.bind
        idx += 1
      end

      if where_expr
        buf << " WHERE "
        idx = compile_expr(where_expr, buf, binds, idx)
      end

      finalize_query(buf, binds, ctes)
    end

    sig do
      params(
        table: String,
        columns: T::Array[FieldRef],
        values: T::Array[T::Array[Bind]],
        returning: T.nilable(FieldRef)
      ).returns(CompiledQuery)
    end
    def insert(table:, columns:, values:, returning: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << "INSERT INTO "
      buf << @dialect.quote_id(table)
      buf << " ("
      columns.each_with_index do |col, i|
        buf << ", " if i.positive?
        buf << @dialect.quote_id(col.column_name)
      end
      buf << ") VALUES "

      values.each_with_index do |row, ri|
        buf << ", " if ri.positive?
        buf << "("
        row.each_with_index do |bind, ci|
          buf << ", " if ci.positive?
          buf << @dialect.bind_marker(idx)
          binds << bind
          idx += 1
        end
        buf << ")"
      end

      if returning
        buf << " RETURNING "
        buf << @dialect.quote_id(returning.column_name)
      end

      CompiledQuery.new(-buf, binds)
    end

    private

    sig { params(field: FieldRef).returns(String) }
    def qualify(field)
      "#{@dialect.quote_id(field.table_name)}.#{@dialect.quote_id(field.column_name)}"
    end

    sig { params(join_type: Symbol).returns(String) }
    def join_keyword(join_type)
      JOIN_KEYWORDS.fetch(join_type, " INNER JOIN ")
    end

    sig { params(buf: String, table: String, table_alias: T.nilable(String)).void }
    def append_table_reference(buf, table, table_alias)
      buf << @dialect.quote_id(table)
      return unless table_alias && table_alias != table

      buf << " AS " << @dialect.quote_id(table_alias)
    end

    sig { params(sql: String, binds: T::Array[Bind], ctes: T::Array[CteEntry]).returns(CompiledQuery) }
    def finalize_query(sql, binds, ctes)
      return CompiledQuery.new(-sql, binds) if ctes.empty?

      cte_clauses = T.let([], T::Array[String])
      cte_binds = T.let([], T::Array[Bind])
      recursive = T.let(false, T::Boolean)

      ctes.each do |name, query, is_recursive|
        recursive ||= is_recursive
        rebased = rebase_binds(query.sql, cte_binds.length)
        cte_clauses << "#{@dialect.quote_id(name)} AS (#{rebased})"
        cte_binds.concat(query.binds)
      end

      main_sql = rebase_binds(sql, cte_binds.length)
      prefix = recursive ? "WITH RECURSIVE " : "WITH "
      all_binds = T.let([], T::Array[Bind])
      all_binds.concat(cte_binds)
      all_binds.concat(binds)
      CompiledQuery.new(-"#{prefix}#{cte_clauses.join(", ")} #{main_sql}", all_binds)
    end
  end
end

require_relative "sql_compiler_expr"
