# typed: strict
# frozen_string_literal: true

# Internal component for codegen/enum_definition.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class EnumDefinition
      extend T::Sig

      sig { returns(String) }
      attr_reader :column_name

      sig { returns(T::Hash[Symbol, Integer]) }
      attr_reader :values

      sig { returns(T.nilable(Symbol)) }
      attr_reader :prefix

      sig { returns(T.nilable(Symbol)) }
      attr_reader :suffix

      sig do
        params(
          column_name: String,
          values: T::Hash[Symbol, Integer],
          prefix: T.nilable(Symbol),
          suffix: T.nilable(Symbol)
        ).void
      end
      def initialize(column_name:, values:, prefix: nil, suffix: nil)
        @column_name = T.let(column_name, String)
        @values = T.let(values, T::Hash[Symbol, Integer])
        @prefix = T.let(prefix, T.nilable(Symbol))
        @suffix = T.let(suffix, T.nilable(Symbol))
      end

      sig { returns(T::Array[String]) }
      def serialized_values
        values.values.map(&:to_s)
      end
    end
  end
end
