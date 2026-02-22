# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    module TypeMaps
      module Mysql
        extend T::Sig

        MAP = T.let({
          "int" => HakumiType::Integer,
          "bigint" => HakumiType::Integer,
          "smallint" => HakumiType::Integer,
          "mediumint" => HakumiType::Integer,
          "tinyint" => HakumiType::Integer,

          "varchar" => HakumiType::String,
          "char" => HakumiType::String,
          "text" => HakumiType::String,
          "mediumtext" => HakumiType::String,
          "longtext" => HakumiType::String,
          "tinytext" => HakumiType::String,

          "tinyint(1)" => HakumiType::Boolean,

          "datetime" => HakumiType::Timestamp,
          "timestamp" => HakumiType::Timestamp,

          "date" => HakumiType::Date,

          "float" => HakumiType::Float,
          "double" => HakumiType::Float,

          "decimal" => HakumiType::Decimal,

          "json" => HakumiType::Json,
          "binary" => HakumiType::String,
          "varbinary" => HakumiType::String,
          "blob" => HakumiType::String,
          "enum" => HakumiType::String,
          "set" => HakumiType::String
        }.freeze, T::Hash[::String, HakumiType])
      end
    end
  end
end
