# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class EnumBuilder
      extend T::Sig

      EnumMappingValue = T.type_alias { T.any(String, Integer, Symbol) }

      sig { returns(String) }
      attr_reader :table_name

      sig { returns(T::Array[EnumDefinition]) }
      attr_reader :definitions

      sig { params(table_name: String).void }
      def initialize(table_name)
        @table_name = T.let(table_name, String)
        @definitions = T.let([], T::Array[EnumDefinition])
      end

      sig { params(column_name: Symbol, prefix: T.nilable(Symbol), suffix: T.nilable(Symbol), values: T.any(String, Integer)).void }
      def enum(column_name, prefix: nil, suffix: nil, **values)
        raise HakumiORM::Error, "Enum :#{column_name} on '#{@table_name}' must have at least one value" if values.empty?

        @definitions << EnumDefinition.new(
          column_name: column_name.to_s,
          values: values,
          prefix: prefix,
          suffix: suffix
        )
      end
    end
  end
end
