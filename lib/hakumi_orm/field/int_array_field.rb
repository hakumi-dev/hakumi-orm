# typed: strict
# frozen_string_literal: true

module HakumiORM
  class IntArrayField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Array[T.nilable(Integer)] } }

    sig { override.params(value: T::Array[T.nilable(Integer)]).returns(Bind) }
    def to_bind(value)
      IntArrayBind.new(value)
    end
  end
end
