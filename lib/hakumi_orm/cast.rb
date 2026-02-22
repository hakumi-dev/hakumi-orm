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
        raw == "t"
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
    end
  end
end
