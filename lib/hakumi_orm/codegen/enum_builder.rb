# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class EnumBuilder
      extend T::Sig

      sig { returns(String) }
      attr_reader :table_name

      sig { returns(T::Array[EnumDefinition]) }
      attr_reader :definitions

      sig { params(table_name: String).void }
      def initialize(table_name)
        @table_name = T.let(table_name, String)
        @definitions = T.let([], T::Array[EnumDefinition])
      end

      sig { params(column_name: Symbol, values: T::Hash[Symbol, Integer], prefix: T.nilable(Symbol), suffix: T.nilable(Symbol)).void }
      def enum(column_name, values, prefix: nil, suffix: nil)
        raise HakumiORM::Error, "Enum :#{column_name} on '#{@table_name}' must have at least one value" if values.empty?

        bad = values.reject { |_, v| v.is_a?(Integer) }
        unless bad.empty?
          raise HakumiORM::Error,
                "Enum :#{column_name} on '#{@table_name}': all values must be integers (sym: int). " \
                "Got non-integer values: #{bad.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")}"
        end

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
