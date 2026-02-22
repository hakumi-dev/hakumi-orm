# typed: strict
# frozen_string_literal: true

module HakumiORM
  class StrArrayField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Array[T.nilable(String)] } }

    sig { override.params(value: T::Array[T.nilable(String)]).returns(Bind) }
    def to_bind(value)
      StrArrayBind.new(value)
    end
  end
end
