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
          map[data_type] || (udt_name && map[udt_name]) || HakumiType::String
        end

        sig { params(hakumi_type: HakumiType, raw_expr: String, nullable: T::Boolean).returns(String) }
        def cast_expression(hakumi_type, raw_expr, nullable:)
          case hakumi_type
          when HakumiType::Integer
            nullable ? "#{raw_expr}&.to_i" : "#{raw_expr}.to_i"
          when HakumiType::Boolean
            if nullable
              "((_hv = #{raw_expr}).nil? ? nil : _hv == \"t\")"
            else
              "#{raw_expr} == \"t\""
            end
          when HakumiType::Float
            nullable ? "#{raw_expr}&.to_f" : "#{raw_expr}.to_f"
          when HakumiType::Decimal
            if nullable
              "((_hv = #{raw_expr}).nil? ? nil : BigDecimal(_hv))"
            else
              "BigDecimal(#{raw_expr})"
            end
          when HakumiType::Timestamp
            if nullable
              "((_hv = #{raw_expr}).nil? ? nil : ::HakumiORM::Cast.to_time(_hv))"
            else
              "::HakumiORM::Cast.to_time(#{raw_expr})"
            end
          when HakumiType::Date
            if nullable
              "((_hv = #{raw_expr}).nil? ? nil : ::HakumiORM::Cast.to_date(_hv))"
            else
              "::HakumiORM::Cast.to_date(#{raw_expr})"
            end
          else
            raw_expr
          end
        end
      end
    end
  end
end
