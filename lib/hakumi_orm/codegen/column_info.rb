# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class ColumnInfo < T::Struct
      const :name, String
      const :data_type, String
      const :udt_name, String
      const :nullable, T::Boolean
      const :default, T.nilable(String)
      const :max_length, T.nilable(Integer)
    end
  end
end
