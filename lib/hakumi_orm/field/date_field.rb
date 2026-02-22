# typed: strict
# frozen_string_literal: true

module HakumiORM
  class DateField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Date } }

    sig { override.params(value: Date).returns(Bind) }
    def to_bind(value)
      DateBind.new(value)
    end
  end
end
