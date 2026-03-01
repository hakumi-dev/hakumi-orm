# typed: strict
# frozen_string_literal: true

# Internal component for codegen/column_info.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class ColumnInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :data_type

      sig { returns(String) }
      attr_reader :udt_name

      sig { returns(T::Boolean) }
      attr_reader :nullable

      sig { returns(T.nilable(String)) }
      attr_reader :default

      sig { returns(T.nilable(Integer)) }
      attr_reader :max_length

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :enum_values

      sig do
        params(
          name: String,
          data_type: String,
          udt_name: String,
          nullable: T::Boolean,
          default: T.nilable(String),
          max_length: T.nilable(Integer),
          enum_values: T.nilable(T::Array[String])
        ).void
      end
      def initialize(name:, data_type:, udt_name:, nullable:, default: nil, max_length: nil, enum_values: nil)
        @name = T.let(name, String)
        @data_type = T.let(data_type, String)
        @udt_name = T.let(udt_name, String)
        @nullable = T.let(nullable, T::Boolean)
        @default = T.let(default, T.nilable(String))
        @max_length = T.let(max_length, T.nilable(Integer))
        @enum_values = T.let(enum_values, T.nilable(T::Array[String]))
      end
    end
  end
end
