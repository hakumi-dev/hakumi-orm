# typed: strict
# frozen_string_literal: true

# Internal component for field.
module HakumiORM
  # Internal class for HakumiORM.
  class Field < FieldRef
    extend T::Sig
    extend T::Helpers
    extend T::Generic

    abstract!

    ValueType = type_member

    sig { abstract.params(value: ValueType).returns(Bind) }
    def to_bind(value); end

    sig { params(value: T.nilable(ValueType)).returns(Predicate) }
    def eq(value)
      Predicate.new(self, :eq, [bind_or_null(value)])
    end

    sig { params(other: T.nilable(ValueType)).returns(Predicate) }
    def ==(other)
      eq(other)
    end

    sig { params(value: T.nilable(ValueType)).returns(Predicate) }
    def neq(value)
      Predicate.new(self, :neq, [bind_or_null(value)])
    end

    sig { params(other: T.nilable(ValueType)).returns(Predicate) }
    def !=(other)
      neq(other)
    end

    sig { params(values: T::Array[T.nilable(ValueType)]).returns(Expr) }
    def in_list(values)
      return RawExpr.new("1 = 0", []) if values.empty?

      Predicate.new(self, :in, values.map { |v| bind_or_null(v) })
    end

    sig { params(values: T::Array[T.nilable(ValueType)]).returns(Expr) }
    def not_in_list(values)
      return RawExpr.new("1 = 1", []) if values.empty?

      Predicate.new(self, :not_in, values.map { |v| bind_or_null(v) })
    end

    sig { returns(Predicate) }
    def is_null
      Predicate.new(self, :is_null, [])
    end

    sig { returns(Predicate) }
    def is_not_null
      Predicate.new(self, :is_not_null, [])
    end

    private

    sig { params(value: T.nilable(ValueType)).returns(Bind) }
    def bind_or_null(value)
      case value
      when nil
        return NullBind.new
      end

      to_bind(value)
    end
  end
end
