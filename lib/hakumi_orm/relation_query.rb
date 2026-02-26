# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Reopens Relation with query support helpers (batching + expr composition).
  class Relation

    private

    sig { params(exprs: T::Array[Expr]).returns(T.nilable(Expr)) }
    def combine_exprs(exprs)
      return nil if exprs.empty?

      result = T.let(exprs.fetch(0), Expr)
      i = T.let(1, Integer)
      while i < exprs.length
        result = AndExpr.new(result, exprs.fetch(i))
        i += 1
      end
      result
    end
  end
end
