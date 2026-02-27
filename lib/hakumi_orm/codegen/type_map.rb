# typed: strict
# frozen_string_literal: true

# Internal component for codegen/type_map.
module HakumiORM
  module Codegen
    # Internal module for HakumiORM.
    module TypeMap
      class << self
        extend T::Sig

        DIALECT_MAPS = T.let({
          postgresql: TypeMaps::Postgresql::MAP,
          mysql: TypeMaps::Mysql::MAP,
          sqlite: TypeMaps::Sqlite::MAP
        }.freeze, T::Hash[Symbol, T::Hash[String, HakumiType]])

        sig { params(dialect: Symbol, data_type: String, udt_name: T.nilable(String)).returns(HakumiType) }
        def hakumi_type(dialect, data_type, udt_name = nil)
          map = DIALECT_MAPS.fetch(dialect) do
            raise ArgumentError, "Unknown dialect: #{dialect}"
          end
          (udt_name && map[udt_name]) || map[data_type] || HakumiType::String
        end

        sig { params(hakumi_type: HakumiType, raw_expr: String, nullable: T::Boolean).returns(String) }
        def cast_expression(hakumi_type, raw_expr, nullable:)
          case hakumi_type
          when HakumiType::Integer     then dialect_cast("cast_integer", raw_expr, nullable)
          when HakumiType::String      then dialect_cast("cast_string", raw_expr, nullable)
          when HakumiType::Boolean     then dialect_cast("cast_boolean", raw_expr, nullable)
          when HakumiType::Float       then dialect_cast("cast_float", raw_expr, nullable)
          when HakumiType::Decimal     then dialect_cast("cast_decimal", raw_expr, nullable)
          when HakumiType::Timestamp   then dialect_cast("cast_time", raw_expr, nullable)
          when HakumiType::Date        then dialect_cast("cast_date", raw_expr, nullable)
          when HakumiType::Json        then dialect_cast("cast_json", raw_expr, nullable)
          when HakumiType::IntegerArray then dialect_cast("cast_int_array", raw_expr, nullable)
          when HakumiType::StringArray  then dialect_cast("cast_str_array", raw_expr, nullable)
          when HakumiType::FloatArray   then dialect_cast("cast_float_array", raw_expr, nullable)
          when HakumiType::BooleanArray then dialect_cast("cast_bool_array", raw_expr, nullable)
          else raw_expr
          end
        end

        private

        sig { params(method_name: String, raw_expr: String, nullable: T::Boolean).returns(String) }
        def dialect_cast(method_name, raw_expr, nullable)
          if nullable
            "((_hv = #{raw_expr}).nil? ? nil : dialect.#{method_name}(_hv))"
          else
            "dialect.#{method_name}(#{raw_expr})"
          end
        end
      end
    end
  end
end
