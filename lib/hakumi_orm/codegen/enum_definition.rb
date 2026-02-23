# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class EnumDefinition < T::Struct
      extend T::Sig

      const :column_name, String
      const :values, T::Hash[Symbol, T.any(String, Integer)]
      const :prefix, T.nilable(Symbol), default: nil
      const :suffix, T.nilable(Symbol), default: nil

      sig { returns(T::Array[String]) }
      def serialized_values
        values.values.map(&:to_s)
      end

      sig { returns(String) }
      def db_type
        first_val = values.values.first
        first_val.is_a?(Integer) ? "integer" : "string"
      end
    end
  end
end
