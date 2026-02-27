# typed: strict
# frozen_string_literal: true

# Internal component for codegen/table_info.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class TableInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { returns(T::Array[ColumnInfo]) }
      attr_reader :columns

      sig { returns(T::Array[ForeignKeyInfo]) }
      attr_reader :foreign_keys

      sig { returns(T::Array[String]) }
      attr_reader :unique_columns

      sig { returns(T.nilable(String)) }
      attr_accessor :primary_key

      sig { params(name: String).void }
      def initialize(name)
        @name = T.let(name, String)
        @columns = T.let([], T::Array[ColumnInfo])
        @foreign_keys = T.let([], T::Array[ForeignKeyInfo])
        @unique_columns = T.let([], T::Array[String])
        @primary_key = T.let(nil, T.nilable(String))
      end
    end
  end
end
