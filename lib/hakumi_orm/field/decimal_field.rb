# typed: strict
# frozen_string_literal: true

module HakumiORM
  class DecimalField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: BigDecimal } }

    sig { override.params(value: BigDecimal).returns(Bind) }
    def to_bind(value)
      DecimalBind.new(value)
    end
  end
end
