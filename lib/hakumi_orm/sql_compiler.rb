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
        offset_val: T.nilable(Integer)
      ).returns(CompiledQuery)
    end
    def select(table:, columns:, where_expr: nil, orders: [], joins: [], limit_val: nil, offset_val: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 256)

      buf << "SELECT "
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
        compile_expr(where_expr, buf, binds, idx)
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

      CompiledQuery.new(-buf, binds)
    end

    sig do
      params(
        table: String,
        where_expr: T.nilable(Expr)
      ).returns(CompiledQuery)
    end
    def count(table:, where_expr: nil)
      binds = T.let([], T::Array[Bind])
      idx = T.let(0, Integer)
      buf = String.new(capacity: 128)

      buf << "SELECT COUNT(*) FROM "
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

    sig { params(expr: Expr, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_expr(expr, buf, binds, idx)
      case expr
      when Predicate then compile_predicate(expr, buf, binds, idx)
      when AndExpr
        buf << "("
        idx = compile_expr(expr.left, buf, binds, idx)
        buf << " AND "
        idx = compile_expr(expr.right, buf, binds, idx)
        buf << ")"
        idx
      when OrExpr
        buf << "("
        idx = compile_expr(expr.left, buf, binds, idx)
        buf << " OR "
        idx = compile_expr(expr.right, buf, binds, idx)
        buf << ")"
        idx
      when NotExpr
        buf << "NOT ("
        idx = compile_expr(expr.inner, buf, binds, idx)
        buf << ")"
        idx
      else
        T.absurd(expr)
      end
    end

    sig { params(pred: Predicate, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_predicate(pred, buf, binds, idx)
      qn = pred.field.qualified_name

      case pred.op
      when :eq
        buf << qn << " = " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :neq
        buf << qn << " <> " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :gt
        buf << qn << " > " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :gte
        buf << qn << " >= " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :lt
        buf << qn << " < " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :lte
        buf << qn << " <= " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :like
        buf << qn << " LIKE " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :ilike
        buf << qn << " ILIKE " << @dialect.bind_marker(idx)
        binds << pred.binds.fetch(0)
        idx + 1
      when :in
        buf << qn << " IN ("
        pred.binds.each_with_index do |b, i|
          buf << ", " if i.positive?
          buf << @dialect.bind_marker(idx + i)
          binds << b
        end
        buf << ")"
        idx + pred.binds.length
      when :not_in
        buf << qn << " NOT IN ("
        pred.binds.each_with_index do |b, i|
          buf << ", " if i.positive?
          buf << @dialect.bind_marker(idx + i)
          binds << b
        end
        buf << ")"
        idx + pred.binds.length
      when :between
        buf << qn << " BETWEEN " << @dialect.bind_marker(idx)
        buf << " AND " << @dialect.bind_marker(idx + 1)
        binds << pred.binds.fetch(0)
        binds << pred.binds.fetch(1)
        idx + 2
      when :is_null
        buf << qn << " IS NULL"
        idx
      when :is_not_null
        buf << qn << " IS NOT NULL"
        idx
      else
        raise ArgumentError, "Unknown predicate operator: #{pred.op}"
      end
    end

    sig { params(join_type: Symbol).returns(String) }
    def join_keyword(join_type)
      JOIN_KEYWORDS.fetch(join_type, " INNER JOIN ")
    end
  end
end
