# typed: strict
# frozen_string_literal: true

module HakumiORM
  class StrField < TextField
    extend T::Sig

    ValueType = type_member { { fixed: String } }

    sig { override.params(value: String).returns(Bind) }
    def to_bind(value)
      StrBind.new(value)
    end
  end
end
