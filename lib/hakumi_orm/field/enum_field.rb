# typed: strict
# frozen_string_literal: true

module HakumiORM
  class EnumField < Field
    extend T::Sig

    ValueType = type_member { { upper: T::Enum } }

    sig { override.params(value: ValueType).returns(Bind) }
    def to_bind(value)
      StrBind.new(T.cast(value.serialize, String))
    end
  end
end
