# typed: strict
# frozen_string_literal: true

module HakumiORM
  class JsonField < Field
    extend T::Sig

    ValueType = type_member { { fixed: Json } }

    sig { override.params(value: Json).returns(Bind) }
    def to_bind(value)
      JsonBind.new(value)
    end
  end
end
