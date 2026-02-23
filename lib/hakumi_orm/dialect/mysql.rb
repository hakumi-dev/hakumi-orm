# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    class Mysql < Base
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
        @id_cache[name] ||= -"`#{name}`"
      end

      sig { override.params(table: String, column: String).returns(String) }
      def qualified_name(table, column)
        key = -"#{table}.#{column}"
        @qn_cache[key] ||= -"`#{table}`.`#{column}`"
      end

      sig { override.returns(T::Boolean) }
      def supports_returning?
        false
      end

      sig { override.returns(Symbol) }
      def name
        :mysql
      end

      sig { override.returns(T::Boolean) }
      def supports_advisory_lock?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def advisory_lock_sql
        "SELECT GET_LOCK('hakumi_migrate', 10)"
      end

      sig { override.returns(T.nilable(String)) }
      def advisory_unlock_sql
        "SELECT RELEASE_LOCK('hakumi_migrate')"
      end

      sig { override.params(value: T::Boolean).returns(PGValue) }
      def encode_boolean(value) = value ? 1 : 0

      sig { override.params(raw: String).returns(T::Boolean) }
      def cast_boolean(raw) = raw == "1"

      sig { override.params(_value: T::Array[T.nilable(Integer)]).returns(PGValue) }
      def encode_int_array(_value) = unsupported!(:integer_array)

      sig { override.params(_value: T::Array[T.nilable(String)]).returns(PGValue) }
      def encode_str_array(_value) = unsupported!(:string_array)

      sig { override.params(_value: T::Array[T.nilable(Float)]).returns(PGValue) }
      def encode_float_array(_value) = unsupported!(:float_array)

      sig { override.params(_value: T::Array[T.nilable(T::Boolean)]).returns(PGValue) }
      def encode_bool_array(_value) = unsupported!(:boolean_array)

      sig { override.params(_raw: String).returns(T::Array[T.nilable(Integer)]) }
      def cast_int_array(_raw) = unsupported!(:integer_array)

      sig { override.params(_raw: String).returns(T::Array[T.nilable(String)]) }
      def cast_str_array(_raw) = unsupported!(:string_array)

      sig { override.params(_raw: String).returns(T::Array[T.nilable(Float)]) }
      def cast_float_array(_raw) = unsupported!(:float_array)

      sig { override.params(_raw: String).returns(T::Array[T.nilable(T::Boolean)]) }
      def cast_bool_array(_raw) = unsupported!(:boolean_array)

      private

      sig { params(type_name: Symbol).returns(T.noreturn) }
      def unsupported!(type_name)
        raise ::HakumiORM::Error, "MySQL does not support #{type_name} columns"
      end
    end
  end
end
