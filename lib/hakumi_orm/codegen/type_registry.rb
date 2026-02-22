# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class TypeRegistryEntry < T::Struct
      const :name, Symbol
      const :ruby_type, String
      const :cast_expression, T.proc.params(raw_expr: String, nullable: T::Boolean).returns(String)
      const :field_class, String
      const :bind_class, String
    end

    module TypeRegistry
      class << self
        extend T::Sig

        sig do
          params(
            name: Symbol,
            ruby_type: String,
            cast_expression: T.proc.params(raw_expr: String, nullable: T::Boolean).returns(String),
            field_class: String,
            bind_class: String
          ).void
        end
        def register(name:, ruby_type:, cast_expression:, field_class:, bind_class:)
          raise ArgumentError, "Type #{name.inspect} is already registered" if registry.key?(name)

          registry[name] = TypeRegistryEntry.new(
            name: name,
            ruby_type: ruby_type,
            cast_expression: cast_expression,
            field_class: field_class,
            bind_class: bind_class
          )
        end

        sig { params(name: Symbol).returns(T::Boolean) }
        def registered?(name)
          registry.key?(name)
        end

        sig { params(name: Symbol).returns(TypeRegistryEntry) }
        def fetch(name)
          registry.fetch(name)
        end

        sig { params(pg_type: String, name: Symbol).void }
        def map_pg_type(pg_type, name)
          pg_map[pg_type] = name
        end

        sig { params(pg_type: String).returns(T.nilable(TypeRegistryEntry)) }
        def resolve_pg(pg_type)
          name = pg_map[pg_type]
          return nil unless name

          registry[name]
        end

        sig { void }
        def reset!
          registry.clear
          pg_map.clear
        end

        private

        sig { returns(T::Hash[Symbol, TypeRegistryEntry]) }
        def registry
          @registry ||= T.let({}, T.nilable(T::Hash[Symbol, TypeRegistryEntry]))
        end

        sig { returns(T::Hash[String, Symbol]) }
        def pg_map
          @pg_map ||= T.let({}, T.nilable(T::Hash[String, Symbol]))
        end
      end
    end
  end
end
