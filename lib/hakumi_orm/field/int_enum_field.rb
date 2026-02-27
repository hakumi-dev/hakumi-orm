# typed: strict
# frozen_string_literal: true

# Internal component for field/int_enum_field.
module HakumiORM
  # Internal class for HakumiORM.
  class IntEnumField < Field
    extend T::Sig

    ValueType = type_member { { upper: T::Enum } }

    sig { override.params(value: ValueType).returns(Bind) }
    def to_bind(value)
      IntBind.new(T.cast(value.serialize, Integer))
    end
  end
end
