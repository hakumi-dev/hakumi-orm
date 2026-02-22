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

      sig { returns(SqlCompiler) }
      def compiler
        @compiler = T.let(@compiler, T.nilable(SqlCompiler))
        @compiler ||= SqlCompiler.new(self)
      end
    end
  end
end
