# typed: strict
# frozen_string_literal: true

# Internal component for codegen/foreign_key_info.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class ForeignKeyInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :column_name

      sig { returns(String) }
      attr_reader :foreign_table

      sig { returns(String) }
      attr_reader :foreign_column

      sig { params(column_name: String, foreign_table: String, foreign_column: String).void }
      def initialize(column_name:, foreign_table:, foreign_column:)
        @column_name = T.let(column_name, String)
        @foreign_table = T.let(foreign_table, String)
        @foreign_column = T.let(foreign_column, String)
      end
    end
  end
end
