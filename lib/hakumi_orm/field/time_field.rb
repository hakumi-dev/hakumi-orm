# typed: strict
# frozen_string_literal: true

# Internal component for field/time_field.
module HakumiORM
  # Internal class for HakumiORM.
  class TimeField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Time } }

    sig { override.params(value: Time).returns(Bind) }
    def to_bind(value)
      TimeBind.new(value)
    end
  end
end
