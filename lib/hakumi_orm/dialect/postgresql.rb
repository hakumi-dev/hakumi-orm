# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    class Postgresql < Base
      extend T::Sig

      # 10^(6-n) lookup for microsecond padding: index = number of fractional digits
      USEC_PAD = T.let([1, 100_000, 10_000, 1_000, 100, 10, 1].freeze, T::Array[Integer])

      sig { void }
      def initialize
        @id_cache = T.let({}, T::Hash[String, String])
        @qn_cache = T.let({}, T::Hash[String, String])
        @marker_cache = T.let({}, T::Hash[Integer, String])
      end

      sig { override.params(raw: String).returns(Time) }
      def cast_time(raw)
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

      sig { override.params(index: Integer).returns(String) }
      def bind_marker(index)
        @marker_cache[index] ||= -"$#{index + 1}"
      end

      sig { override.params(name: String).returns(String) }
      def quote_id(name)
        @id_cache[name] ||= -"\"#{name}\""
      end

      sig { override.params(table: String, column: String).returns(String) }
      def qualified_name(table, column)
        key = -"#{table}.#{column}"
        @qn_cache[key] ||= -"\"#{table}\".\"#{column}\""
      end

      sig { override.returns(T::Boolean) }
      def supports_returning?
        true
      end

      sig { override.returns(T::Boolean) }
      def supports_cursors?
        true
      end

      sig { override.returns(T::Boolean) }
      def supports_ddl_transactions?
        true
      end

      sig { override.returns(T::Boolean) }
      def supports_advisory_lock?
        true
      end

      MIGRATION_LOCK_KEY = 7_283_482_910

      sig { override.returns(T.nilable(String)) }
      def advisory_lock_sql
        "SELECT pg_advisory_lock(#{MIGRATION_LOCK_KEY})"
      end

      sig { override.returns(T.nilable(String)) }
      def advisory_unlock_sql
        "SELECT pg_advisory_unlock(#{MIGRATION_LOCK_KEY})"
      end

      sig { override.returns(Symbol) }
      def name
        :postgresql
      end
    end
  end
end
