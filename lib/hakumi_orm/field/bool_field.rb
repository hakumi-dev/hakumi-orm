# typed: strict
# frozen_string_literal: true

# Internal component for field/bool_field.
module HakumiORM
  # Internal class for HakumiORM.
  class BoolField < Field
    extend T::Sig

    ValueType = type_member { { fixed: T::Boolean } }

    sig { override.params(value: T::Boolean).returns(Bind) }
    def to_bind(value)
      BoolBind.new(value)
    end
  end
end
