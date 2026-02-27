# typed: strict
# frozen_string_literal: true

# Internal component for field/date_field.
module HakumiORM
  # Internal class for HakumiORM.
  class DateField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Date } }

    sig { override.params(value: Date).returns(Bind) }
    def to_bind(value)
      DateBind.new(value)
    end
  end
end
