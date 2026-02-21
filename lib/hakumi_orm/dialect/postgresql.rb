# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    class Postgresql < Base
      extend T::Sig

      MARKERS = T.let((1..500).map { |i| -"$#{i}" }.freeze, T::Array[String])

      sig { void }
      def initialize
        @id_cache = T.let({}, T::Hash[String, String])
        @qn_cache = T.let({}, T::Hash[String, String])
      end

      sig { override.params(index: Integer).returns(String) }
      def bind_marker(index)
        T.must(MARKERS[index])
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

      sig { override.returns(Symbol) }
      def name
        :postgresql
      end
    end
  end
end
