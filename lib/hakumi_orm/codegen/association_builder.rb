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
        params(name: String, opts: T.untyped).void
      end
      def has_many(name, **opts)
        add_association(name, :has_many, opts)
      end

      sig do
        params(name: String, opts: T.untyped).void
      end
      def has_one(name, **opts)
        add_association(name, :has_one, opts)
      end

      private

      sig { params(name: String, kind: Symbol, opts: T::Hash[Symbol, T.untyped]).void }
      def add_association(name, kind, opts)
        @associations << CustomAssociation.new(
          name: name,
          target_table: String(opts.fetch(:target)),
          foreign_key: String(opts.fetch(:foreign_key)),
          primary_key: String(opts.fetch(:primary_key)),
          kind: kind,
          order_by: opts[:order_by]&.to_s,
          scope: opts[:scope]&.to_s
        )
      end
    end
  end
end
