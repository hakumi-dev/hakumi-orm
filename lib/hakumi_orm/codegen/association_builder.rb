# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
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

      sig do
        params(
          name: String,
          target: String,
          foreign_key: String,
          primary_key: String,
          order_by: T.nilable(String)
        ).void
      end
      def has_many(name, target:, foreign_key:, primary_key:, order_by: nil)
        @associations << CustomAssociation.new(
          name: name,
          target_table: target,
          foreign_key: foreign_key,
          primary_key: primary_key,
          kind: :has_many,
          order_by: order_by
        )
      end

      sig do
        params(
          name: String,
          target: String,
          foreign_key: String,
          primary_key: String,
          order_by: T.nilable(String)
        ).void
      end
      def has_one(name, target:, foreign_key:, primary_key:, order_by: nil)
        @associations << CustomAssociation.new(
          name: name,
          target_table: target,
          foreign_key: foreign_key,
          primary_key: primary_key,
          kind: :has_one,
          order_by: order_by
        )
      end
    end
  end
end
