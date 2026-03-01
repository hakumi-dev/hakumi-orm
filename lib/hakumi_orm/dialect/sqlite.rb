# typed: strict
# frozen_string_literal: true

# Internal component for dialect/sqlite.
module HakumiORM
  module Dialect
    # Internal class for HakumiORM.
    class Sqlite < Base
      extend T::Sig

      sig { void }
      def initialize
        @id_cache = T.let({}, T::Hash[String, String])
        @qn_cache = T.let({}, T::Hash[String, String])
        @marker_cache = T.let({}, T::Hash[Integer, String])
      end

      sig { override.params(index: Integer).returns(String) }
      def bind_marker(index)
        @marker_cache[index] ||= -"?"
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
      def supports_ddl_transactions?
        true
      end

      sig { override.returns(Symbol) }
      def name
        :sqlite
      end

      sig { override.params(value: T::Boolean).returns(DBValue) }
      def encode_boolean(value) = value ? 1 : 0

      sig { override.params(value: Time).returns(DBValue) }
      def encode_time(value) = value.utc.strftime("%Y-%m-%d %H:%M:%S")

      sig { override.params(raw: Adapter::CellValue).returns(T::Boolean) }
      def cast_boolean(raw)
        return raw if raw.equal?(true) || raw.equal?(false)
        return !raw.zero? if raw.is_a?(Integer)

        raw == "1"
      end

      sig { override.params(_value: T::Array[T.nilable(Integer)]).returns(DBValue) }
      def encode_int_array(_value) = unsupported!(:integer_array)

      sig { override.params(_value: T::Array[T.nilable(String)]).returns(DBValue) }
      def encode_str_array(_value) = unsupported!(:string_array)

      sig { override.params(_value: T::Array[T.nilable(Float)]).returns(DBValue) }
      def encode_float_array(_value) = unsupported!(:float_array)

      sig { override.params(_value: T::Array[T.nilable(T::Boolean)]).returns(DBValue) }
      def encode_bool_array(_value) = unsupported!(:boolean_array)

      sig { override.params(_raw: Adapter::CellValue).returns(T::Array[T.nilable(Integer)]) }
      def cast_int_array(_raw) = unsupported!(:integer_array)

      sig { override.params(_raw: Adapter::CellValue).returns(T::Array[T.nilable(String)]) }
      def cast_str_array(_raw) = unsupported!(:string_array)

      sig { override.params(_raw: Adapter::CellValue).returns(T::Array[T.nilable(Float)]) }
      def cast_float_array(_raw) = unsupported!(:float_array)

      sig { override.params(_raw: Adapter::CellValue).returns(T::Array[T.nilable(T::Boolean)]) }
      def cast_bool_array(_raw) = unsupported!(:boolean_array)

      private

      sig { params(type_name: Symbol).returns(T.noreturn) }
      def unsupported!(type_name)
        raise ::HakumiORM::Error, "SQLite does not support #{type_name} columns"
      end
    end
  end
end
