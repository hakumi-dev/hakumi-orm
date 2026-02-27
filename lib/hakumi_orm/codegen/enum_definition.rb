# typed: strict
# frozen_string_literal: true

# Internal component for codegen/enum_definition.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class EnumDefinition < T::Struct
      extend T::Sig

      const :column_name, String
      const :values, T::Hash[Symbol, Integer]
      const :prefix, T.nilable(Symbol), default: nil
      const :suffix, T.nilable(Symbol), default: nil

      sig { returns(T::Array[String]) }
      def serialized_values
        values.values.map(&:to_s)
      end
    end
  end
end
