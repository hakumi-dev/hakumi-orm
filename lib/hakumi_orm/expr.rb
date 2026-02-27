# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Base node for boolean expressions used in WHERE and HAVING clauses.
  class Expr
    extend T::Sig
    extend T::Helpers

    abstract!
    sealed!

    sig { params(other: Expr).returns(AndExpr) }
    def and(other)
      AndExpr.new(self, other)
    end

    sig { params(other: Expr).returns(AndExpr) }
    def &(other)
      self.and(other)
    end

    sig { params(other: Expr).returns(OrExpr) }
    def or(other)
      OrExpr.new(self, other)
    end

    sig { params(other: Expr).returns(OrExpr) }
    def |(other)
      self.or(other)
    end

    sig { returns(NotExpr) }
    def not
      NotExpr.new(self)
    end

    sig { returns(NotExpr) }
    def !
      self.not
    end
  end

  # Field predicate with operation and typed bind values.
  class Predicate < Expr
    extend T::Sig

    sig { returns(FieldRef) }
    attr_reader :field

    sig { returns(Symbol) }
    attr_reader :op

    sig { returns(T::Array[Bind]) }
    attr_reader :binds

    sig { params(field: FieldRef, op: Symbol, binds: T::Array[Bind]).void }
    def initialize(field, op, binds)
      @field = T.let(field, FieldRef)
      @op = T.let(op, Symbol)
      @binds = T.let(binds, T::Array[Bind])
    end
  end

  # Logical conjunction of two expressions.
  class AndExpr < Expr
    extend T::Sig

    sig { returns(Expr) }
    attr_reader :left

    sig { returns(Expr) }
    attr_reader :right

    sig { params(left: Expr, right: Expr).void }
    def initialize(left, right)
      @left = T.let(left, Expr)
      @right = T.let(right, Expr)
    end
  end

  # Logical disjunction of two expressions.
  class OrExpr < Expr
    extend T::Sig

    sig { returns(Expr) }
    attr_reader :left

    sig { returns(Expr) }
    attr_reader :right

    sig { params(left: Expr, right: Expr).void }
    def initialize(left, right)
      @left = T.let(left, Expr)
      @right = T.let(right, Expr)
    end
  end

  # Logical negation of an expression.
  class NotExpr < Expr
    extend T::Sig

    sig { returns(Expr) }
    attr_reader :inner

    sig { params(inner: Expr).void }
    def initialize(inner)
      @inner = T.let(inner, Expr)
    end
  end

  # Unsafe SQL fragment with placeholder count validation.
  class RawExpr < Expr
    extend T::Sig

    SQL_QUOTED_OR_PLACEHOLDER = T.let(
      %r{'(?:''|[^'])*'|"(?:""|[^"])*"|--[^\n]*|/\*(?:[^*]|\*(?!/))*\*/|\?},
      Regexp
    )

    sig { returns(String) }
    attr_reader :sql

    sig { returns(T::Array[Bind]) }
    attr_reader :binds

    sig { params(sql: String, binds: T::Array[Bind]).void }
    def initialize(sql, binds = [])
      placeholders = sql.scan(SQL_QUOTED_OR_PLACEHOLDER).count("?")
      if placeholders != binds.length
        raise ArgumentError,
              "RawExpr placeholder count (#{placeholders}) does not match bind count (#{binds.length}) in: #{sql}"
      end

      @sql = T.let(sql, String)
      @binds = T.let(binds, T::Array[Bind])
    end
  end

  # Predicate against a compiled subquery.
  class SubqueryExpr < Expr
    extend T::Sig

    sig { returns(FieldRef) }
    attr_reader :field

    sig { returns(Symbol) }
    attr_reader :op

    sig { returns(CompiledQuery) }
    attr_reader :subquery

    sig { params(field: FieldRef, op: Symbol, subquery: CompiledQuery).void }
    def initialize(field, op, subquery)
      @field = T.let(field, FieldRef)
      @op = T.let(op, Symbol)
      @subquery = T.let(subquery, CompiledQuery)
    end
  end
end
