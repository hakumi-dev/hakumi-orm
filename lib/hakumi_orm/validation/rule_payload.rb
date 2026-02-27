# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    RulePayload = T.type_alias do
      T::Hash[Symbol, T.nilable(T.any(Symbol, String, Integer, Float, Regexp, T::Boolean, Proc, T::Array[Object]))]
    end
  end
end
