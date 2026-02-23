# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Zero-alloc timestamp parser — pure byte arithmetic, no substring allocations.
  # Expects ISO 8601-like format: "YYYY-MM-DD HH:MM:SS[.USEC][+TZ]"
  module ByteTime
    class << self
      extend T::Sig

      # 10^(6-n) lookup for microsecond padding: index = number of fractional digits
      USEC_PAD = T.let([1, 100_000, 10_000, 1_000, 100, 10, 1].freeze, T::Array[Integer])

      sig { params(raw: String).returns(Time) }
      def parse_utc(raw)
        Time.utc(
          read4(raw, 0), read2(raw, 5), read2(raw, 8),
          read2(raw, 11), read2(raw, 14), read2(raw, 17),
          read_usec(raw)
        )
      end

      private

      sig { params(raw: String, offset: Integer).returns(Integer) }
      def read4(raw, offset)
        ((raw.getbyte(offset).to_i - 48) * 1000) +
          ((raw.getbyte(offset + 1).to_i - 48) * 100) +
          ((raw.getbyte(offset + 2).to_i - 48) * 10) +
          (raw.getbyte(offset + 3).to_i - 48)
      end

      sig { params(raw: String, offset: Integer).returns(Integer) }
      def read2(raw, offset)
        ((raw.getbyte(offset).to_i - 48) * 10) + (raw.getbyte(offset + 1).to_i - 48)
      end

      sig { params(raw: String).returns(Integer) }
      def read_usec(raw)
        return 0 unless raw.bytesize > 20 && raw.getbyte(19) == 46 # '.'

        usec = 0
        n = 0
        pos = 20
        while pos < raw.bytesize && pos < 26
          byte = raw.getbyte(pos)

          break if byte.nil? || byte < 48 || byte > 57

          usec = (usec * 10) + (byte - 48)
          n += 1
          pos += 1
        end
        n.positive? ? usec * USEC_PAD.fetch(n, 1) : 0
      end
    end
  end
end
