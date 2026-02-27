# typed: strict
# frozen_string_literal: true

# Internal component for field/decimal_field.
module HakumiORM
  # Internal class for HakumiORM.
  class DecimalField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: BigDecimal } }

    sig { override.params(value: BigDecimal).returns(Bind) }
    def to_bind(value)
      DecimalBind.new(value)
    end
  end
end
