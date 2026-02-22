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

      sig { override.params(bind: ::HakumiORM::Bind).returns(::HakumiORM::PGValue) }
      def encode_bind(bind)
        case bind
        when ::HakumiORM::BoolBind then bind.value ? 1 : 0
        else bind.pg_value
        end
      end
    end
  end
end
