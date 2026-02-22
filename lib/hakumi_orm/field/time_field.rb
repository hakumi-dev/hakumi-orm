# typed: strict
# frozen_string_literal: true

module HakumiORM
  class TimeField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Time } }

    sig { override.params(value: Time).returns(Bind) }
    def to_bind(value)
      TimeBind.new(value)
    end
  end
end
