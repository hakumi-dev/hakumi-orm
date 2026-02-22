# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class ForeignKeyInfo < T::Struct
      const :column_name, String
      const :foreign_table, String
      const :foreign_column, String
    end
  end
end
