# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

module HakumiORM
  module Cast
    class << self
      extend T::Sig

      sig { params(raw: String).returns(Integer) }
      def to_integer(raw)
        raw.to_i
      end

      sig { params(raw: String).returns(Float) }
      def to_float(raw)
        raw.to_f
      end

      sig { params(raw: String).returns(BigDecimal) }
      def to_decimal(raw)
        BigDecimal(raw)
      end

      sig { params(raw: String).returns(T::Boolean) }
      def to_boolean(raw)
        raw == "t" || raw == "1" || raw == "true"
      end

      sig { params(raw: String).returns(Time) }
      def to_time(raw)
        Time.parse(raw).utc
      end

      sig { params(raw: String).returns(Date) }
      def to_date(raw)
        Date.parse(raw)
      end

      sig { params(raw: String).returns(String) }
      def to_string(raw)
        raw
      end

      sig { params(raw: String).returns(Json) }
      def to_json(raw)
        Json.parse(raw)
      end

      sig { params(raw: String).returns(T::Array[T.nilable(Integer)]) }
      def to_int_array(raw)
        parse_pg_array(raw).map { |v| v&.to_i }
      end

      sig { params(raw: String).returns(T::Array[T.nilable(String)]) }
      def to_str_array(raw)
        parse_pg_array(raw)
      end

      sig { params(raw: String).returns(T::Array[T.nilable(Float)]) }
      def to_float_array(raw)
        parse_pg_array(raw).map { |v| v&.to_f }
      end

      sig { params(raw: String).returns(T::Array[T.nilable(T::Boolean)]) }
      def to_bool_array(raw)
        parse_pg_array(raw).map { |v| v.nil? ? nil : v == "t" }
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
            elements << resolve_element(current)
            current = +""
          else
            current << ch
          end
        end
        elements << resolve_element(current)
        elements
      end

      sig { params(element: String).returns(T.nilable(String)) }
      def resolve_element(element)
        element == "NULL" ? nil : element
      end
    end
  end
end
