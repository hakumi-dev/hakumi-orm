# typed: strict
# frozen_string_literal: true

module HakumiORM
  class BoolArrayField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Array[T.nilable(T::Boolean)] } }

    sig { override.params(value: T::Array[T.nilable(T::Boolean)]).returns(Bind) }
    def to_bind(value)
      BoolArrayBind.new(value)
    end
  end
end
