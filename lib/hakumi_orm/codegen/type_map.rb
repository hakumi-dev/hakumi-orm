# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
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
          when HakumiType::Integer
            nullable ? "#{raw_expr}&.to_i" : "#{raw_expr}.to_i"
          when HakumiType::Boolean
            nullable_cast("::HakumiORM::Cast.to_boolean", raw_expr, nullable)
          when HakumiType::Float
            nullable ? "#{raw_expr}&.to_f" : "#{raw_expr}.to_f"
          when HakumiType::Decimal   then nullable_cast("BigDecimal", raw_expr, nullable)
          when HakumiType::Timestamp then nullable_cast("::HakumiORM::Cast.to_time", raw_expr, nullable)
          when HakumiType::Date      then nullable_cast("::HakumiORM::Cast.to_date", raw_expr, nullable)
          when HakumiType::Json         then nullable_cast("::HakumiORM::Cast.to_json", raw_expr, nullable)
          when HakumiType::IntegerArray then nullable_cast("::HakumiORM::Cast.to_int_array", raw_expr, nullable)
          when HakumiType::StringArray  then nullable_cast("::HakumiORM::Cast.to_str_array", raw_expr, nullable)
          when HakumiType::FloatArray   then nullable_cast("::HakumiORM::Cast.to_float_array", raw_expr, nullable)
          when HakumiType::BooleanArray then nullable_cast("::HakumiORM::Cast.to_bool_array", raw_expr, nullable)
          else raw_expr
          end
        end

        private

        sig { params(cast_fn: String, raw_expr: String, nullable: T::Boolean).returns(String) }
        def nullable_cast(cast_fn, raw_expr, nullable)
          if nullable
            "((_hv = #{raw_expr}).nil? ? nil : #{cast_fn}(_hv))"
          else
            "#{cast_fn}(#{raw_expr})"
          end
        end
      end
    end
  end
end
