# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    module TypeMaps
      module Postgresql
        extend T::Sig

        MAP = T.let({
          "integer" => HakumiType::Integer,
          "bigint" => HakumiType::Integer,
          "smallint" => HakumiType::Integer,
          "serial" => HakumiType::Integer,
          "bigserial" => HakumiType::Integer,
          "int2" => HakumiType::Integer,
          "int4" => HakumiType::Integer,
          "int8" => HakumiType::Integer,
          "oid" => HakumiType::Integer,

          "character varying" => HakumiType::String,
          "varchar" => HakumiType::String,
          "text" => HakumiType::String,
          "char" => HakumiType::String,
          "bpchar" => HakumiType::String,
          "character" => HakumiType::String,
          "name" => HakumiType::String,

          "boolean" => HakumiType::Boolean,
          "bool" => HakumiType::Boolean,

          "timestamp without time zone" => HakumiType::Timestamp,
          "timestamp with time zone" => HakumiType::Timestamp,
          "timestamptz" => HakumiType::Timestamp,
          "timestamp" => HakumiType::Timestamp,

          "date" => HakumiType::Date,

          "double precision" => HakumiType::Float,
          "real" => HakumiType::Float,
          "float4" => HakumiType::Float,
          "float8" => HakumiType::Float,

          "numeric" => HakumiType::Decimal,
          "decimal" => HakumiType::Decimal,
          "money" => HakumiType::Decimal,

          "json" => HakumiType::Json,
          "jsonb" => HakumiType::Json,
          "uuid" => HakumiType::Uuid,
          "bytea" => HakumiType::String,
          "inet" => HakumiType::String,
          "cidr" => HakumiType::String,
          "macaddr" => HakumiType::String,
          "hstore" => HakumiType::String,
          "interval" => HakumiType::String,
          "xml" => HakumiType::String,
          "tsvector" => HakumiType::String,
          "tsquery" => HakumiType::String,
          "time without time zone" => HakumiType::String,
          "time with time zone" => HakumiType::String,

          "ARRAY" => HakumiType::StringArray,

          "_int2" => HakumiType::IntegerArray,
          "_int4" => HakumiType::IntegerArray,
          "_int8" => HakumiType::IntegerArray,
          "_integer" => HakumiType::IntegerArray,

          "_text" => HakumiType::StringArray,
          "_varchar" => HakumiType::StringArray,
          "_bpchar" => HakumiType::StringArray,
          "_name" => HakumiType::StringArray,

          "_float4" => HakumiType::FloatArray,
          "_float8" => HakumiType::FloatArray,
          "_numeric" => HakumiType::FloatArray,

          "_bool" => HakumiType::BooleanArray
        }.freeze, T::Hash[::String, HakumiType])
      end
    end
  end
end
