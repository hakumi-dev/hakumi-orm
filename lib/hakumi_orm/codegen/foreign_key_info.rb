# typed: strict
# frozen_string_literal: true

# Internal component for codegen/foreign_key_info.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class ForeignKeyInfo < T::Struct
      const :column_name, String
      const :foreign_table, String
      const :foreign_column, String
    end
  end
end
