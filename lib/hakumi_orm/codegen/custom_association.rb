# typed: strict
# frozen_string_literal: true

# Internal component for codegen/custom_association.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class CustomAssociation
      extend T::Sig

      VALID_KINDS = T.let(%i[has_many has_one].freeze, T::Array[Symbol])
      VALID_NAME_PATTERN = T.let(/\A[a-z_]\w*\z/, Regexp)

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :target_table

      sig { returns(String) }
      attr_reader :foreign_key

      sig { returns(String) }
      attr_reader :primary_key

      sig { returns(Symbol) }
      attr_reader :kind

      sig { returns(T.nilable(String)) }
      attr_reader :order_by

      sig { returns(T.nilable(String)) }
      attr_reader :scope

      sig do
        params(
          name: String,
          target_table: String,
          foreign_key: String,
          primary_key: String,
          kind: Symbol,
          order_by: T.nilable(String),
          scope: T.nilable(String)
        ).void
      end
      def initialize(name:, target_table:, foreign_key:, primary_key:, kind:, order_by: nil, scope: nil)
        @name = T.let(name, String)
        @target_table = T.let(target_table, String)
        @foreign_key = T.let(foreign_key, String)
        @primary_key = T.let(primary_key, String)
        @kind = T.let(kind, Symbol)
        @order_by = T.let(order_by, T.nilable(String))
        @scope = T.let(scope, T.nilable(String))
      end
    end
  end
end
