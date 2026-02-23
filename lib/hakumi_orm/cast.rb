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

      TRUTHY = T.let(%w[t 1 true].to_set.freeze, T::Set[String])

      sig { params(raw: String).returns(T::Boolean) }
      def to_boolean(raw)
        TRUTHY.include?(raw)
      end

      # 10^(6-n) lookup for microsecond padding
      USEC_PAD = T.let([1, 100_000, 10_000, 1_000, 100, 10, 1].freeze, T::Array[Integer])

      sig { params(raw: String).returns(Time) }
      def to_time(raw)
        len = raw.bytesize
        usec = 0

        if len > 19
          i = 20
          while i < len && i < 26
            byte = raw.getbyte(i)

            break if byte.nil? || byte < 48 || byte > 57

            i += 1
          end
          ndigits = i - 20
          if ndigits.positive?
            frac_s = raw[20, ndigits]
            usec = frac_s.to_i * USEC_PAD.fetch(ndigits, 1) if frac_s
          end
        end

        Time.utc(raw[0, 4].to_i, raw[5, 2].to_i, raw[8, 2].to_i,
                 raw[11, 2].to_i, raw[14, 2].to_i, raw[17, 2].to_i, usec)
      end

      sig { params(raw: String).returns(Date) }
      def to_date(raw)
        Date.new(raw[0, 4].to_i, raw[5, 2].to_i, raw[8, 2].to_i)
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
