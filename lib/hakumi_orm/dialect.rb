# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

module HakumiORM
  module Dialect
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.params(index: Integer).returns(String) }
      def bind_marker(index); end

      sig { abstract.params(name: String).returns(String) }
      def quote_id(name); end

      sig { abstract.params(table: String, column: String).returns(String) }
      def qualified_name(table, column); end

      sig { abstract.returns(T::Boolean) }
      def supports_returning?; end

      sig { abstract.returns(Symbol) }
      def name; end

      sig { returns(T::Boolean) }
      def supports_cursors?
        false
      end

      sig { returns(T::Boolean) }
      def supports_ddl_transactions?
        false
      end

      sig { returns(T::Boolean) }
      def supports_advisory_lock?
        false
      end

      sig { returns(T.nilable(String)) }
      def advisory_lock_sql
        nil
      end

      sig { returns(T.nilable(String)) }
      def advisory_unlock_sql
        nil
      end

      # -- Encoding: Ruby → DB wire format --

      sig { overridable.params(value: Integer).returns(PGValue) }
      def encode_integer(value) = value

      sig { overridable.params(value: String).returns(PGValue) }
      def encode_string(value) = value

      sig { overridable.params(value: T::Boolean).returns(PGValue) }
      def encode_boolean(value) = value ? "t" : "f"

      sig { overridable.params(value: Time).returns(PGValue) }
      def encode_time(value) = value.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")

      sig { overridable.params(value: Date).returns(PGValue) }
      def encode_date(value) = value.iso8601

      sig { overridable.params(value: Float).returns(PGValue) }
      def encode_float(value) = value

      sig { overridable.params(value: BigDecimal).returns(PGValue) }
      def encode_decimal(value) = value.to_s("F")

      sig { overridable.params(value: Json).returns(PGValue) }
      def encode_json(value) = value.to_json

      sig { overridable.params(value: T::Array[T.nilable(Integer)]).returns(PGValue) }
      def encode_int_array(value) = "{#{value.map { |v| v.nil? ? "NULL" : v.to_s }.join(",")}}"

      sig { overridable.params(value: T::Array[T.nilable(String)]).returns(PGValue) }
      def encode_str_array(value)
        inner = value.map do |v|
          if v.nil?
            "NULL"
          elsif v.include?(",") || v.include?('"') || v.include?("\\") || v.include?(" ")
            "\"#{v.gsub("\\", "\\\\\\\\").gsub('"', '\\"')}\""
          else
            v
          end
        end
        "{#{inner.join(",")}}"
      end

      sig { overridable.params(value: T::Array[T.nilable(Float)]).returns(PGValue) }
      def encode_float_array(value) = "{#{value.map { |v| v.nil? ? "NULL" : v.to_s }.join(",")}}"

      sig { overridable.params(value: T::Array[T.nilable(T::Boolean)]).returns(PGValue) }
      def encode_bool_array(value)
        inner = value.map do |v|
          if v.nil? then "NULL"
          elsif v then "t"
          else "f"
          end
        end
        "{#{inner.join(",")}}"
      end

      # -- Decoding: DB raw string → Ruby type --

      sig { overridable.params(raw: String).returns(Integer) }
      def cast_integer(raw) = raw.to_i

      sig { overridable.params(raw: String).returns(String) }
      def cast_string(raw) = raw

      sig { overridable.params(raw: String).returns(T::Boolean) }
      def cast_boolean(raw) = raw == "t"

      sig { overridable.params(raw: String).returns(Time) }
      def cast_time(raw) = Time.parse(raw).utc

      sig { overridable.params(raw: String).returns(Date) }
      def cast_date(raw) = Date.parse(raw)

      sig { overridable.params(raw: String).returns(Float) }
      def cast_float(raw) = raw.to_f

      sig { overridable.params(raw: String).returns(BigDecimal) }
      def cast_decimal(raw) = BigDecimal(raw)

      sig { overridable.params(raw: String).returns(Json) }
      def cast_json(raw) = Json.parse(raw)

      sig { overridable.params(raw: String).returns(T::Array[T.nilable(Integer)]) }
      def cast_int_array(raw) = parse_pg_array(raw).map { |v| v&.to_i }

      sig { overridable.params(raw: String).returns(T::Array[T.nilable(String)]) }
      def cast_str_array(raw) = parse_pg_array(raw)

      sig { overridable.params(raw: String).returns(T::Array[T.nilable(Float)]) }
      def cast_float_array(raw) = parse_pg_array(raw).map { |v| v&.to_f }

      sig { overridable.params(raw: String).returns(T::Array[T.nilable(T::Boolean)]) }
      def cast_bool_array(raw) = parse_pg_array(raw).map { |v| v.nil? ? nil : v == "t" }

      # -- Bind dispatch --

      sig { params(bind: Bind).returns(PGValue) }
      def encode_bind(bind)
        case bind
        when IntBind
          v = bind.value
          v.nil? ? nil : encode_integer(v)
        when StrBind then encode_string(bind.value)
        when BoolBind then encode_boolean(bind.value)
        when TimeBind then encode_time(bind.value)
        when DateBind then encode_date(bind.value)
        when FloatBind then encode_float(bind.value)
        when DecimalBind then encode_decimal(bind.value)
        when JsonBind then encode_json(bind.value)
        when NullBind then nil
        when IntArrayBind then encode_int_array(bind.value)
        when StrArrayBind then encode_str_array(bind.value)
        when FloatArrayBind then encode_float_array(bind.value)
        when BoolArrayBind then encode_bool_array(bind.value)
        else T.absurd(bind)
        end
      end

      sig { params(binds: T::Array[Bind]).returns(T::Array[PGValue]) }
      def encode_binds(binds)
        binds.map { |b| encode_bind(b) }
      end

      sig { returns(SqlCompiler) }
      def compiler
        @compiler ||= T.let(SqlCompiler.new(self), T.nilable(SqlCompiler))
      end

      private

      sig { params(raw: String).returns(T::Array[T.nilable(String)]) }
      def parse_pg_array(raw)
        inner = raw[1...-1]
        return [] if inner.nil? || inner.empty?

        elements = T.let([], T::Array[T.nilable(String)])
        current = +""
        in_quotes = T.let(false, T::Boolean)
        escaped = T.let(false, T::Boolean)

        inner.each_char do |ch|
          if escaped
            current << ch
            escaped = false
          elsif ch == "\\"
            escaped = true
          elsif ch == '"'
            in_quotes = !in_quotes
          elsif ch == "," && !in_quotes
            elements << (current == "NULL" ? nil : current)
            current = +""
          else
            current << ch
          end
        end
        elements << (current == "NULL" ? nil : current)
        elements
      end
    end
  end
end
