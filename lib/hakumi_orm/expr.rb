# typed: strict
# frozen_string_literal: true

module HakumiORM
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
      # self. required: `and` is a Ruby keyword
      self.and(other)
    end

    sig { params(other: Expr).returns(OrExpr) }
    def or(other)
      OrExpr.new(self, other)
    end

    sig { params(other: Expr).returns(OrExpr) }
    def |(other)
      # self. required: `or` is a Ruby keyword
      self.or(other)
    end

    sig { returns(NotExpr) }
    def not
      NotExpr.new(self)
    end

    sig { returns(NotExpr) }
    def !
      # self. required: `not` is a Ruby keyword
      self.not
    end
  end

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

  class NotExpr < Expr
    extend T::Sig

    sig { returns(Expr) }
    attr_reader :inner

    sig { params(inner: Expr).void }
    def initialize(inner)
      @inner = T.let(inner, Expr)
    end
  end
end
