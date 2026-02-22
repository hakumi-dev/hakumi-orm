# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class CustomAssociation < T::Struct
      VALID_KINDS = T.let(%i[has_many has_one].freeze, T::Array[Symbol])
      VALID_NAME_PATTERN = T.let(/\A[a-z_]\w*\z/, Regexp)

      const :name, String
      const :target_table, String
      const :foreign_key, String
      const :primary_key, String
      const :kind, Symbol
      const :order_by, T.nilable(String), default: nil
    end
  end
end
