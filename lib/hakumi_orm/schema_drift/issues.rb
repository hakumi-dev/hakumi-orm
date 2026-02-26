# typed: strict
# frozen_string_literal: true

module HakumiORM
  module SchemaDrift
    # Issue type for unapplied migrations.
    class PendingMigrationsIssue < T::Struct
      const :versions, T::Array[String]
    end

    # Issue type for databases missing a stored schema fingerprint.
    class NoSchemaFingerprintIssue < T::Struct; end

    # Issue type for stored/live schema fingerprint mismatches.
    class SchemaMismatchIssue < T::Struct
      const :expected_fingerprint, String
      const :actual_fingerprint, String
      const :diff_lines, T::Array[String]
    end

    # Union of all schema drift issue variants.
    Issue = T.type_alias { T.any(PendingMigrationsIssue, NoSchemaFingerprintIssue, SchemaMismatchIssue) }
  end
end
