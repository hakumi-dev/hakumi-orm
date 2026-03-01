# typed: strict
# frozen_string_literal: true

# Internal component for migration/column_definition.
module HakumiORM
  class Migration
    # Internal class for HakumiORM.
    class ColumnDefinition
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(Symbol) }
      attr_reader :type

      sig { returns(T::Boolean) }
      attr_reader :null

      sig { returns(T.nilable(String)) }
      attr_reader :default

      sig { returns(T.nilable(Integer)) }
      attr_reader :limit

      sig { returns(T.nilable(Integer)) }
      attr_reader :precision

      sig { returns(T.nilable(Integer)) }
      attr_reader :scale

      sig do
        params(
          name: String,
          type: Symbol,
          null: T::Boolean,
          default: T.nilable(String),
          limit: T.nilable(Integer),
          precision: T.nilable(Integer),
          scale: T.nilable(Integer)
        ).void
      end
      def initialize(name:, type:, null: true, default: nil, limit: nil, precision: nil, scale: nil)
        @name = T.let(name, String)
        @type = T.let(type, Symbol)
        @null = T.let(null, T::Boolean)
        @default = T.let(default, T.nilable(String))
        @limit = T.let(limit, T.nilable(Integer))
        @precision = T.let(precision, T.nilable(Integer))
        @scale = T.let(scale, T.nilable(Integer))
      end
    end
  end
end
