# typed: strict
# frozen_string_literal: true

module HakumiORM
  class SqlCompiler
    extend T::Sig

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
    def select(table:, columns:, where_expr: nil, orders: [], joins: [], limit_val: nil, offset_val: nil,
               distinct: false, lock: nil, group_fields: [], having_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << (distinct ? "SELECT DISTINCT " : "SELECT ")
      columns.each_with_index do |col, i|
        buf << ", " if i.positive?
        buf << col.qualified_name
      end

      buf << " FROM "
      buf << @dialect.quote_id(table)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << j.source_field.qualified_name
        buf << " = "
        buf << j.target_field.qualified_name
      end

      if where_expr
        buf << " WHERE "
        idx = compile_expr(where_expr, buf, binds, idx)
      end

      unless group_fields.empty?
        buf << " GROUP BY "
        group_fields.each_with_index do |f, i|
          buf << ", " if i.positive?
          buf << f.qualified_name
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
          buf << o.field.qualified_name
          buf << (o.direction == :desc ? " DESC" : " ASC")
        end
      end

      buf << " LIMIT " << limit_val.to_s if limit_val
      buf << " OFFSET " << offset_val.to_s if offset_val
      buf << " " << lock if lock

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        function: String,
        field: FieldRef,
        where_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def aggregate(table:, function:, field:, where_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT " << function << "(" << field.qualified_name << ") FROM "
      buf << @dialect.quote_id(table)

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        where_expr: T.nilable(Expr),
        joins: T::Array[JoinClause]
      ).returns(CompiledQuery)
    end
    def count(table:, where_expr: nil, joins: [])
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT COUNT(*) FROM "
      buf << @dialect.quote_id(table)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << j.source_field.qualified_name
        buf << " = "
        buf << j.target_field.qualified_name
      end

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        where_expr: T.nilable(Expr),
        joins: T::Array[JoinClause]
      ).returns(CompiledQuery)
    end
    def exists(table:, where_expr: nil, joins: [])
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT 1 FROM "
      buf << @dialect.quote_id(table)

      joins.each do |j|
        buf << join_keyword(j.join_type)
        buf << @dialect.quote_id(j.target_table)
        buf << " ON "
        buf << j.source_field.qualified_name
        buf << " = "
        buf << j.target_field.qualified_name
      end

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      buf << " LIMIT 1"

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        where_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def delete(table:, where_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "DELETE FROM "
      buf << @dialect.quote_id(table)

      if where_expr
        buf << " WHERE "
        compile_expr(where_expr, buf, binds, idx)
      end

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        assignments: T::Array[Assignment],
        where_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def update(table:, assignments:, where_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << "UPDATE "
      buf << @dialect.quote_id(table)
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

      CompiledQuery.new(-buf, binds)
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

    sig { params(join_type: Symbol).returns(String) }
    def join_keyword(join_type)
      JOIN_KEYWORDS.fetch(join_type, " INNER JOIN ")
    end
  end
end

require_relative "sql_compiler_expr"
