# typed: strict
# frozen_string_literal: true

module HakumiORM
  module SchemaDrift
    # Issue type for unapplied migrations.
    class PendingMigrationsIssue
      extend T::Sig

      sig { returns(T::Array[String]) }
      attr_reader :versions

      sig { params(versions: T::Array[String]).void }
      def initialize(versions:)
        @versions = T.let(versions, T::Array[String])
      end
    end

    # Issue type for databases missing a stored schema fingerprint.
    class NoSchemaFingerprintIssue
      extend T::Sig

      sig { void }
      def initialize; end
    end

    # Issue type for stored/live schema fingerprint mismatches.
    class SchemaMismatchIssue
      extend T::Sig

      sig { returns(String) }
      attr_reader :expected_fingerprint

      sig { returns(String) }
      attr_reader :actual_fingerprint

      sig { returns(T::Array[String]) }
      attr_reader :diff_lines

      sig do
        params(
          expected_fingerprint: String,
          actual_fingerprint: String,
          diff_lines: T::Array[String]
        ).void
      end
      def initialize(expected_fingerprint:, actual_fingerprint:, diff_lines:)
        @expected_fingerprint = T.let(expected_fingerprint, String)
        @actual_fingerprint = T.let(actual_fingerprint, String)
        @diff_lines = T.let(diff_lines, T::Array[String])
      end
    end

    # Union of all schema drift issue variants.
    Issue = T.type_alias { T.any(PendingMigrationsIssue, NoSchemaFingerprintIssue, SchemaMismatchIssue) }
  end
end
