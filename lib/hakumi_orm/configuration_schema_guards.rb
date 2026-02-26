# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Configuration methods that enforce schema safety checks at boot.
  class Configuration
    extend T::Sig

    private

    sig { params(adapter: Adapter::Base).void }
    def verify_schema_fingerprint!(adapter)
      expected = @schema_fingerprint
      return unless expected

      actual = Migration::SchemaFingerprint.read_from_db(adapter)
      return unless actual

      Migration::SchemaFingerprint.check!(expected, actual)
    end

    sig { params(adapter: Adapter::Base).void }
    def verify_no_pending_migrations!(adapter)
      return unless @schema_fingerprint

      pending = Migration::SchemaFingerprint.pending_migrations(adapter, @migrations_path)
      return if pending.empty?

      raise PendingMigrationError, pending
    end
  end
end
