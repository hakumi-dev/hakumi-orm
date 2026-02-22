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

    sig { params(values: T::Array[ValueType]).returns(Predicate) }
    def in_list(values)
      Predicate.new(self, :in, values.map { |v| to_bind(v) })
    end

    sig { params(values: T::Array[ValueType]).returns(Predicate) }
    def not_in_list(values)
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

  class TextField < Field
    extend T::Sig
    extend T::Helpers

    abstract!

    ValueType = type_member

    sig { params(pattern: String).returns(Predicate) }
    def like(pattern)
      Predicate.new(self, :like, [StrBind.new(pattern)])
    end

    sig { params(pattern: String).returns(Predicate) }
    def ilike(pattern)
      Predicate.new(self, :ilike, [StrBind.new(pattern)])
    end
  end

  class IntField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Integer } }

    sig { override.params(value: Integer).returns(Bind) }
    def to_bind(value)
      IntBind.new(value)
    end
  end

  class FloatField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Float } }

    sig { override.params(value: Float).returns(Bind) }
    def to_bind(value)
      FloatBind.new(value)
    end
  end

  class DecimalField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: BigDecimal } }

    sig { override.params(value: BigDecimal).returns(Bind) }
    def to_bind(value)
      DecimalBind.new(value)
    end
  end

  class TimeField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Time } }

    sig { override.params(value: Time).returns(Bind) }
    def to_bind(value)
      TimeBind.new(value)
    end
  end

  class DateField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Date } }

    sig { override.params(value: Date).returns(Bind) }
    def to_bind(value)
      DateBind.new(value)
    end
  end

  class StrField < TextField
    extend T::Sig

    ValueType = type_member { { fixed: String } }

    sig { override.params(value: String).returns(Bind) }
    def to_bind(value)
      StrBind.new(value)
    end
  end

  class BoolField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Boolean } }

    sig { override.params(value: T::Boolean).returns(Bind) }
    def to_bind(value)
      BoolBind.new(value)
    end
  end
end
