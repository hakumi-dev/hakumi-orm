# typed: strict
# frozen_string_literal: true

module HakumiORM
  module SchemaDrift
    class PendingMigrationsIssue < T::Struct
      const :versions, T::Array[String]
    end

    class NoSchemaFingerprintIssue < T::Struct; end

    class SchemaMismatchIssue < T::Struct
      const :expected_fingerprint, String
      const :actual_fingerprint, String
      const :diff_lines, T::Array[String]
    end

    Issue = T.type_alias { T.any(PendingMigrationsIssue, NoSchemaFingerprintIssue, SchemaMismatchIssue) }
  end
end
