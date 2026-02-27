# typed: strict
# frozen_string_literal: true

# Internal component for codegen/association_builder.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class AssociationBuilder
      extend T::Sig

      sig { returns(String) }
      attr_reader :table_name

      sig { returns(T::Array[CustomAssociation]) }
      attr_reader :associations

      sig { params(table_name: String).void }
      def initialize(table_name)
        @table_name = T.let(table_name, String)
        @associations = T.let([], T::Array[CustomAssociation])
      end

      AssocValue = T.type_alias { T.any(String, Symbol) }

      sig do
        params(
          name: String, target: AssocValue, foreign_key: AssocValue,
          primary_key: AssocValue, order_by: T.nilable(AssocValue), scope: T.nilable(AssocValue)
        ).void
      end
      def has_many(name, target:, foreign_key:, primary_key:, order_by: nil, scope: nil)
        build_assoc(name, :has_many, target, foreign_key, primary_key, order_by, scope)
      end

      sig do
        params(
          name: String, target: AssocValue, foreign_key: AssocValue,
          primary_key: AssocValue, order_by: T.nilable(AssocValue), scope: T.nilable(AssocValue)
        ).void
      end
      def has_one(name, target:, foreign_key:, primary_key:, order_by: nil, scope: nil)
        build_assoc(name, :has_one, target, foreign_key, primary_key, order_by, scope)
      end

      private

      sig do
        params(
          name: String, kind: Symbol, target: AssocValue, fk: AssocValue,
          pk: AssocValue, order_by: T.nilable(AssocValue), scope: T.nilable(AssocValue)
        ).void
      end
      def build_assoc(name, kind, target, fk, pk, order_by, scope)
        @associations << CustomAssociation.new(
          name: name,
          target_table: String(target),
          foreign_key: String(fk),
          primary_key: String(pk),
          kind: kind,
          order_by: order_by&.to_s,
          scope: scope&.to_s
        )
      end
    end
  end
end
