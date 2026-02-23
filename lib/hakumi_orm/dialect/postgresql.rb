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

      # PG::TypeMapByColumn decodes boolean/time/date at C level, so these
      # only run on the cold path (schema reads) where raw is always a String.

      sig { override.params(raw: String).returns(T::Boolean) }
      def cast_boolean(raw)
        TRUTHY.include?(raw)
      end

      sig { override.params(raw: String).returns(Time) }
      def cast_time(raw)
        ByteTime.parse_utc(raw)
      end

      sig { override.params(raw: String).returns(Date) }
      def cast_date(raw)
        Date.new(raw[0, 4].to_i, raw[5, 2].to_i, raw[8, 2].to_i)
      end
    end
  end
end
