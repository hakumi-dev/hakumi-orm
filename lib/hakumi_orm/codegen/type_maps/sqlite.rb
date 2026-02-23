# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    module TypeMaps
      module Sqlite
        extend T::Sig

        MAP = T.let({
          "INTEGER" => HakumiType::Integer,
          "TEXT" => HakumiType::String,
          "REAL" => HakumiType::Float,
          "BLOB" => HakumiType::String,
          "NUMERIC" => HakumiType::Decimal,
          "DECIMAL" => HakumiType::Decimal,
          "BOOLEAN" => HakumiType::Boolean,
          "DATE" => HakumiType::Date,
          "DATETIME" => HakumiType::Timestamp
        }.freeze, T::Hash[::String, HakumiType])
      end
    end
  end
end
