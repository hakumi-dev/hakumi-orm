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

      policy = Migration::SchemaFingerprint.drift_allowed? ? :warn : @drift_policy
      Migration::SchemaFingerprint.check!(expected, actual, policy: policy)
    end

    sig { params(adapter: Adapter::Base).void }
    def verify_no_pending_migrations!(adapter)
      return unless @schema_fingerprint

      pending = Migration::SchemaFingerprint.pending_migrations(adapter, @migrations_path)
      return if pending.empty?

      policy = Migration::SchemaFingerprint.drift_allowed? ? :warn : @drift_policy
      case policy
      when :warn
        HakumiORM.config.logger&.warn("HakumiORM: Pending migrations detected but bypassed: #{pending.join(", ")}.")
      when :ignore
        nil
      else
        raise PendingMigrationError, pending
      end
    end
  end
end
