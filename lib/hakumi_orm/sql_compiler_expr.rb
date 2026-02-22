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
      qn = pred.field.qualified_name

      case pred.op
      when :eq       then compile_simple_op(qn, " = ", pred, buf, binds, idx)
      when :neq      then compile_simple_op(qn, " <> ", pred, buf, binds, idx)
      when :gt       then compile_simple_op(qn, " > ", pred, buf, binds, idx)
      when :gte      then compile_simple_op(qn, " >= ", pred, buf, binds, idx)
      when :lt       then compile_simple_op(qn, " < ", pred, buf, binds, idx)
      when :lte      then compile_simple_op(qn, " <= ", pred, buf, binds, idx)
      when :like     then compile_simple_op(qn, " LIKE ", pred, buf, binds, idx)
      when :ilike    then compile_simple_op(qn, " ILIKE ", pred, buf, binds, idx)
      when :in       then compile_list_op(qn, " IN (", pred, buf, binds, idx)
      when :not_in   then compile_list_op(qn, " NOT IN (", pred, buf, binds, idx)
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
        qn: String, prefix: String, pred: Predicate,
        buf: String, binds: T::Array[Bind], idx: Integer
      ).returns(Integer)
    end
    def compile_list_op(qn, prefix, pred, buf, binds, idx)
      buf << qn << prefix
      pred.binds.each_with_index do |b, i|
        buf << ", " if i.positive?
        buf << @dialect.bind_marker(idx + i)
        binds << b
      end
      buf << ")"
      idx + pred.binds.length
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
      fragment = expr.sql.dup
      expr.binds.each do |b|
        fragment.sub!("?", @dialect.bind_marker(idx))
        binds << b
        idx += 1
      end
      buf << fragment
      idx
    end

    sig { params(expr: SubqueryExpr, buf: String, binds: T::Array[Bind], idx: Integer).returns(Integer) }
    def compile_subquery_expr(expr, buf, binds, idx)
      sub = expr.subquery
      buf << expr.field.qualified_name
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

      sql.gsub(/\$(\d+)/) { |_| @dialect.bind_marker(offset + (::Regexp.last_match(1).to_i - 1)) }
    end
  end
end
