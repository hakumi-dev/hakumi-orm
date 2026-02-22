# typed: strict
# frozen_string_literal: true

module HakumiORM
  class FloatField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Float } }

    sig { override.params(value: Float).returns(Bind) }
    def to_bind(value)
      FloatBind.new(value)
    end
  end
end
