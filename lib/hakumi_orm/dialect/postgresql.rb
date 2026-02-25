# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    class Postgresql < Base
      extend T::Sig

      sig { void }
      def initialize
        @id_cache = T.let({}, T::Hash[String, String])
        @qn_cache = T.let({}, T::Hash[String, String])
        @marker_cache = T.let({}, T::Hash[Integer, String])
      end

      sig { override.params(index: Integer).returns(String) }
      def bind_marker(index)
        @marker_cache[index] ||= -"$#{index + 1}"
      end

      sig { override.params(name: String).returns(String) }
      def quote_id(name)
        @id_cache[name] ||= -"\"#{name.gsub('"', '""')}\""
      end

      sig { override.params(table: String, column: String).returns(String) }
      def qualified_name(table, column)
        key = -"#{table}.#{column}"
        @qn_cache[key] ||= -"\"#{table.gsub('"', '""')}\".\"#{column.gsub('"', '""')}\""
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

      # PG::TypeMapByColumn decodes boolean/time/date at C level, delivering
      # native Ruby types. The generated from_result still calls cast_* so
      # these guards pass through pre-decoded values without re-parsing.

      sig { override.params(raw: Adapter::CellValue).returns(T::Boolean) }
      def cast_boolean(raw)
        return raw if raw.equal?(true) || raw.equal?(false)
        raise TypeError, "Expected boolean-like cell, got #{raw.class}" unless raw.is_a?(String)

        TRUTHY.include?(raw)
      end

      sig { override.params(raw: Adapter::CellValue).returns(Time) }
      def cast_time(raw)
        return raw if raw.is_a?(Time)
        raise TypeError, "Expected time-like cell, got #{raw.class}" unless raw.is_a?(String)

        ByteTime.parse_utc(raw)
      end

      sig { override.params(raw: Adapter::CellValue).returns(Date) }
      def cast_date(raw)
        return raw if raw.is_a?(Date)
        raise TypeError, "Expected date-like cell, got #{raw.class}" unless raw.is_a?(String)

        Date.new(raw[0, 4].to_i, raw[5, 2].to_i, raw[8, 2].to_i)
      end
    end
  end
end
