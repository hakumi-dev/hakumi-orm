# typed: strict
# frozen_string_literal: true

module HakumiORM
  class IntField < ComparableField
    extend T::Sig

    ValueType = type_member { { fixed: Integer } }

    sig { override.params(value: Integer).returns(Bind) }
    def to_bind(value)
      IntBind.new(value)
    end
  end
end
