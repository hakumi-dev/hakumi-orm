# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Dialect
    # Abstract interface for database-specific SQL syntax.
    # Each supported database implements this to handle:
    #   - Identifier quoting ("col" vs `col`)
    #   - Bind parameter markers ($1 vs ?)
    #   - Feature support (RETURNING, etc.)
    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      # Returns the bind parameter placeholder at the given 0-based index.
      sig { abstract.params(index: Integer).returns(String) }
      def bind_marker(index); end

      # Quotes a single identifier (table or column name).
      sig { abstract.params(name: String).returns(String) }
      def quote_id(name); end

      # Returns a precomputed "table"."column" qualified name.
      sig { abstract.params(table: String, column: String).returns(String) }
      def qualified_name(table, column); end

      # Whether the database supports RETURNING on INSERT/UPDATE/DELETE.
      sig { abstract.returns(T::Boolean) }
      def supports_returning?; end

      # Symbolic identifier for this dialect.
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
