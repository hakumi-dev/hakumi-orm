# typed: strict
# frozen_string_literal: true

require "pg"

# Internal component for adapter/postgresql_result.
module HakumiORM
  module Adapter
    # Internal class for HakumiORM.
    class PostgresqlResult < Result
      extend T::Sig

      DECODER_BUILDERS = T.let(
        {
          "PG::TextDecoder::Integer.new" => -> { PG::TextDecoder::Integer.new },
          "PG::TextDecoder::Float.new" => -> { PG::TextDecoder::Float.new },
          "PG::TextDecoder::Boolean.new" => -> { PG::TextDecoder::Boolean.new },
          "PG::TextDecoder::Date.new" => -> { PG::TextDecoder::Date.new },
          "PG::TextDecoder::TimestampUtc.new" => -> { PG::TextDecoder::TimestampUtc.new }
        }.freeze,
        T::Hash[String, T.proc.returns(Object)]
      )

      sig { params(decoder_exprs: T::Array[T.nilable(String)]).returns(T.nilable(Object)) }
      def self.build_type_map_from_exprs(decoder_exprs)
        decoders = T.let([], T::Array[T.nilable(Object)])
        decoder_exprs.each do |expr|
          if expr.nil?
            decoders << nil
            next
          end

          builder = DECODER_BUILDERS[expr]
          raise ::HakumiORM::Error, "Unknown PG decoder expr: #{expr}" unless builder

          decoders << builder.call
        end
        PG::TypeMapByColumn.new(decoders)
      rescue ::NameError
        nil
      end

      sig { params(pg_result: PG::Result).void }
      def initialize(pg_result)
        @pg_result = T.let(pg_result, PG::Result)
        @typed = T.let(false, T::Boolean)
        @values_cache = T.let(nil, T.nilable(T::Array[T::Array[CellValue]]))
      end

      sig { override.params(type_map: Object).void }
      def apply_type_map!(type_map)
        return if @typed
        return unless type_map.is_a?(PG::TypeMapByColumn)

        @pg_result.map_types!(type_map)
        @typed = true
        @values_cache = nil
      end

      sig { override.returns(Integer) }
      def row_count
        @pg_result.ntuples
      end

      sig { override.params(row: Integer, col: Integer).returns(CellValue) }
      def get_value(row, col)
        @pg_result.getvalue(row, col)
      end

      sig { override.returns(T::Array[T::Array[CellValue]]) }
      def values
        cached = @values_cache
        return cached if cached

        vals = @pg_result.values
        @values_cache = vals
        vals
      end

      sig { override.params(col: Integer).returns(T::Array[CellValue]) }
      def column_values(col)
        @pg_result.column_values(col)
      end

      sig { override.returns(Integer) }
      def affected_rows
        @pg_result.cmd_tuples
      end

      sig { override.void }
      def close
        @values_cache = nil
        @pg_result.clear
      end
    end
  end
end
