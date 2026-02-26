# typed: strict
# frozen_string_literal: true

module HakumiORM
  class SqlCompiler
    private

    sig { params(expr: Expr, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_expr(expr, buf, binds, idx)
      case expr
      when Predicate then compile_predicate(expr, buf, binds, idx)
      when AndExpr   then compile_binary(expr.left, " AND ", expr.right, buf, binds, idx)
      when OrExpr    then compile_binary(expr.left, " OR ", expr.right, buf, binds, idx)
      when NotExpr
        buf << "NOT ("
        idx = compile_expr(expr.inner, buf, binds, idx)
        buf << ")"
        idx
      when RawExpr
        compile_raw_expr(expr, buf, binds, idx)
      when SubqueryExpr
        compile_subquery_expr(expr, buf, binds, idx)
      else
        T.absurd(expr)
      end
    end

    sig do
      params(
        left: Expr, operator: String, right: Expr,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_binary(left, operator, right, buf, binds, idx)
      buf << "("
      idx = compile_expr(left, buf, binds, idx)
      buf << operator
      idx = compile_expr(right, buf, binds, idx)
      buf << ")"
      idx
    end

    sig { params(pred: Predicate, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_predicate(pred, buf, binds, idx)
      qn = qualify(pred.field)

      case pred.op
      when :eq       then compile_eq_or_neq(qn, pred, equal_op: true, buf: buf, binds: binds, idx: idx)
      when :neq      then compile_eq_or_neq(qn, pred, equal_op: false, buf: buf, binds: binds, idx: idx)
      when :gt       then compile_simple_op(qn, " > ", pred, buf, binds, idx)
      when :gte      then compile_simple_op(qn, " >= ", pred, buf, binds, idx)
      when :lt       then compile_simple_op(qn, " < ", pred, buf, binds, idx)
      when :lte      then compile_simple_op(qn, " <= ", pred, buf, binds, idx)
      when :like     then compile_simple_op(qn, " LIKE ", pred, buf, binds, idx)
      when :ilike    then compile_simple_op(qn, " ILIKE ", pred, buf, binds, idx)
      when :in       then compile_in_or_not_in(qn, pred, in_op: true, buf: buf, binds: binds, idx: idx)
      when :not_in   then compile_in_or_not_in(qn, pred, in_op: false, buf: buf, binds: binds, idx: idx)
      when :between  then compile_between(qn, pred, buf, binds, idx)
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

    sig do
      params(
        qn: String, pred: Predicate, equal_op: T::Boolean,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_eq_or_neq(qn, pred, equal_op:, buf:, binds:, idx:)
      bind = pred.binds.fetch(0)
      if null_bind?(bind)
        buf << qn << (equal_op ? " IS NULL" : " IS NOT NULL")
        idx
      else
        compile_simple_op(qn, equal_op ? " = " : " <> ", pred, buf, binds, idx)
      end
    end

    sig do
      params(
        qn: String, op: String, pred: Predicate,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_simple_op(qn, op, pred, buf, binds, idx)
      buf << qn << op << @dialect.bind_marker(idx)
      binds << pred.binds.fetch(0)
      idx + 1
    end

    sig do
      params(
        qn: String, pred: Predicate, in_op: T::Boolean,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_in_or_not_in(qn, pred, in_op:, buf:, binds:, idx:)
      non_null_binds = T.let([], T::Array[Bind])
      saw_null = T.let(false, T::Boolean)

      pred.binds.each do |bind|
        if null_bind?(bind)
          saw_null = true
        else
          non_null_binds << bind
        end
      end

      if non_null_binds.empty?
        buf << qn << (in_op ? " IS NULL" : " IS NOT NULL")
        return idx
      end

      unless saw_null
        return compile_bind_list_op(qn, in_op ? " IN (" : " NOT IN (", non_null_binds, buf, binds, idx)
      end

      buf << "("
      idx = compile_bind_list_op(qn, in_op ? " IN (" : " NOT IN (", non_null_binds, buf, binds, idx)
      buf << (in_op ? " OR " : " AND ")
      buf << qn << (in_op ? " IS NULL" : " IS NOT NULL")
      buf << ")"
      idx
    end

    sig do
      params(
        qn: String, prefix: String, pred: Predicate,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_list_op(qn, prefix, pred, buf, binds, idx)
      compile_bind_list_op(qn, prefix, pred.binds, buf, binds, idx)
    end

    sig do
      params(
        qn: String, prefix: String, list_binds: T::Array[Bind],
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_bind_list_op(qn, prefix, list_binds, buf, binds, idx)
      buf << qn << prefix
      list_binds.each_with_index do |b, i|
        buf << ", " if i.positive?
        buf << @dialect.bind_marker(idx + i)
        binds << b
      end
      buf << ")"
      idx + list_binds.length
    end

    sig do
      params(
        qn: String, pred: Predicate,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_between(qn, pred, buf, binds, idx)
      buf << qn << " BETWEEN " << @dialect.bind_marker(idx)
      buf << " AND " << @dialect.bind_marker(idx + 1)
      binds << pred.binds.fetch(0)
      binds << pred.binds.fetch(1)
      idx + 2
    end

    sig { params(expr: RawExpr, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_raw_expr(expr, buf, binds, idx)
      bind_offset = T.let(0, Integer)
      compiled = expr.sql.gsub(RawExpr::SQL_QUOTED_OR_PLACEHOLDER) do |match|
        if match == "?"
          binds << expr.binds.fetch(bind_offset)
          bind_offset += 1
          marker = @dialect.bind_marker(idx)
          idx += 1
          marker
        else
          match
        end
      end
      buf << compiled
      idx
    end

    sig { params(expr: SubqueryExpr, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_subquery_expr(expr, buf, binds, idx)
      sub = expr.subquery
      buf << qualify(expr.field)
      buf << (expr.op == :in ? " IN (" : " NOT IN (")
      rebased_sql = rebase_binds(sub.sql, idx)
      buf << rebased_sql
      binds.concat(sub.binds)
      buf << ")"
      idx + sub.binds.length
    end

    sig { params(sql: String, offset: Integer).returns(String) }
    def rebase_binds(sql, offset)
      return sql if offset.zero?

      sql.gsub(SQL_QUOTED_OR_BIND_MARKER) do |match|
        if match.start_with?("$")
          @dialect.bind_marker(offset + (match.delete_prefix("$").to_i - 1))
        else
          match
        end
      end
    end

    sig { params(bind: Bind).returns(T::Boolean) }
    def null_bind?(bind)
      bind.pg_value.nil?
    end
  end
end
