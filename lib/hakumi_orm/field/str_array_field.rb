# typed: strict
# frozen_string_literal: true

# Internal component for field/str_array_field.
module HakumiORM
  # Internal class for HakumiORM.
  class StrArrayField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Array[T.nilable(String)] } }

    sig { override.params(value: T::Array[T.nilable(String)]).returns(Bind) }
    def to_bind(value)
      StrArrayBind.new(value)
    end
  end
end
