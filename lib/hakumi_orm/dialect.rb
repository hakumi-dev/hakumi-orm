# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.params(index: Integer).returns(String) }
      def bind_marker(index); end

      sig { abstract.params(name: String).returns(String) }
      def quote_id(name); end

      sig { abstract.params(table: String, column: String).returns(String) }
      def qualified_name(table, column); end

      sig { abstract.returns(T::Boolean) }
      def supports_returning?; end

      sig { abstract.returns(Symbol) }
      def name; end

      sig { returns(T::Boolean) }
      def supports_cursors?
        false
      end

      sig { params(bind: Bind).returns(PGValue) }
      def encode_bind(bind)
        bind.pg_value
      end

      sig { params(binds: T::Array[Bind]).returns(T::Array[PGValue]) }
      def encode_binds(binds)
        binds.map { |b| encode_bind(b) }
      end

      sig { returns(SqlCompiler) }
      def compiler
        @compiler ||= T.let(SqlCompiler.new(self), T.nilable(SqlCompiler))
      end
    end
  end
end
