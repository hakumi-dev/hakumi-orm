# typed: strict
# frozen_string_literal: true

module HakumiORM
  class ComparableField < Field
    extend T::Sig
    extend T::Helpers

    abstract!

    ValueType = type_member

    sig { params(value: ValueType).returns(Predicate) }
    def gt(value)
      Predicate.new(self, :gt, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def >(other)
      gt(other)
    end

    sig { params(value: ValueType).returns(Predicate) }
    def gte(value)
      Predicate.new(self, :gte, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def >=(other)
      gte(other)
    end

    sig { params(value: ValueType).returns(Predicate) }
    def lt(value)
      Predicate.new(self, :lt, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def <(other)
      lt(other)
    end

    sig { params(value: ValueType).returns(Predicate) }
    def lte(value)
      Predicate.new(self, :lte, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def <=(other)
      lte(other)
    end

    sig { params(low: ValueType, high: ValueType).returns(Predicate) }
    def between(low, high)
      Predicate.new(self, :between, [to_bind(low), to_bind(high)])
    end
  end
end
