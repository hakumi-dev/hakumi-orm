# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
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
      def supports_ddl_transactions?
        true
      end

      sig { override.returns(Symbol) }
      def name
        :sqlite
      end

      sig { override.params(value: T::Boolean).returns(PGValue) }
      def encode_boolean(value) = value ? 1 : 0

      sig { override.params(value: Time).returns(PGValue) }
      def encode_time(value) = value.utc.strftime("%Y-%m-%d %H:%M:%S")

      sig { override.params(raw: String).returns(T::Boolean) }
      def cast_boolean(raw) = raw == "1"

      sig { override.params(value: T::Array[T.nilable(Integer)]).returns(PGValue) }
      def encode_int_array(value) = unsupported!(:integer_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(value: T::Array[T.nilable(String)]).returns(PGValue) }
      def encode_str_array(value) = unsupported!(:string_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(value: T::Array[T.nilable(Float)]).returns(PGValue) }
      def encode_float_array(value) = unsupported!(:float_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(value: T::Array[T.nilable(T::Boolean)]).returns(PGValue) }
      def encode_bool_array(value) = unsupported!(:boolean_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(raw: String).returns(T::Array[T.nilable(Integer)]) }
      def cast_int_array(raw) = unsupported!(:integer_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(raw: String).returns(T::Array[T.nilable(String)]) }
      def cast_str_array(raw) = unsupported!(:string_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(raw: String).returns(T::Array[T.nilable(Float)]) }
      def cast_float_array(raw) = unsupported!(:float_array) # rubocop:disable Lint/UnusedMethodArgument

      sig { override.params(raw: String).returns(T::Array[T.nilable(T::Boolean)]) }
      def cast_bool_array(raw) = unsupported!(:boolean_array) # rubocop:disable Lint/UnusedMethodArgument

      private

      sig { params(type_name: Symbol).returns(T.noreturn) }
      def unsupported!(type_name)
        raise ::HakumiORM::Error, "SQLite does not support #{type_name} columns"
      end
    end
  end
end
