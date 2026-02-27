# typed: strict
# frozen_string_literal: true

# Internal component for field/float_array_field.
module HakumiORM
  # Internal class for HakumiORM.
  class FloatArrayField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Array[T.nilable(Float)] } }

    sig { override.params(value: T::Array[T.nilable(Float)]).returns(Bind) }
    def to_bind(value)
      FloatArrayBind.new(value)
    end
  end
end
