# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    BelongsToEntry = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }

    TemplateScalar = T.type_alias { T.nilable(T.any(String, Integer, T::Boolean)) }

    TemplateCollection = T.type_alias do
      T.any(
        T::Array[String],
        T::Array[T::Hash[Symbol, String]],
        T::Array[BelongsToEntry]
      )
    end

    TemplateLocal = T.type_alias { T.any(TemplateScalar, TemplateCollection) }
  end
end
