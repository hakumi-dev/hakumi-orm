# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Field < FieldRef
    extend T::Sig
    extend T::Helpers
    extend T::Generic

    abstract!

    ValueType = type_member

    sig { abstract.params(value: ValueType).returns(Bind) }
    def to_bind(value); end

    sig { params(value: ValueType).returns(Predicate) }
    def eq(value)
      Predicate.new(self, :eq, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def ==(other)
      eq(other)
    end

    sig { params(value: ValueType).returns(Predicate) }
    def neq(value)
      Predicate.new(self, :neq, [to_bind(value)])
    end

    sig { params(other: ValueType).returns(Predicate) }
    def !=(other)
      neq(other)
    end

    sig { params(values: T::Array[ValueType]).returns(Expr) }
    def in_list(values)
      return RawExpr.new("1 = 0", []) if values.empty?

      Predicate.new(self, :in, values.map { |v| to_bind(v) })
    end

    sig { params(values: T::Array[ValueType]).returns(Expr) }
    def not_in_list(values)
      return RawExpr.new("1 = 1", []) if values.empty?

      Predicate.new(self, :not_in, values.map { |v| to_bind(v) })
    end

    sig { returns(Predicate) }
    def is_null
      Predicate.new(self, :is_null, [])
    end

    sig { returns(Predicate) }
    def is_not_null
      Predicate.new(self, :is_not_null, [])
    end
  end
end
