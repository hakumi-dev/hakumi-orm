# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    # A single belongs_to association descriptor passed to ERB templates.
    # Unlike has_many (all-String values), belongs_to includes :nullable (Boolean).
    BelongsToEntry = T.type_alias { T::Hash[Symbol, T.any(String, T::Boolean)] }

    # Scalar values that appear directly in ERB template locals.
    TemplateScalar = T.type_alias { T.nilable(T.any(String, Integer, T::Boolean)) }

    # Collection values that appear in ERB template locals.
    TemplateCollection = T.type_alias do
      T.any(
        T::Array[String],
        T::Array[T::Hash[Symbol, String]],
        T::Array[BelongsToEntry]
      )
    end

    # Union of every concrete type that may appear as an ERB template local value.
    TemplateLocal = T.type_alias { T.any(TemplateScalar, TemplateCollection) }
  end
end
