# typed: strict
# frozen_string_literal: true

# Internal component for pending_migration_error.
module HakumiORM
  # Internal class for HakumiORM.
  class PendingMigrationError < Error
    extend T::Sig

    sig { params(pending_versions: T::Array[String]).void }
    def initialize(pending_versions)
      count = pending_versions.size
      list = pending_versions.first(5).join(", ")
      suffix = count > 5 ? " (and #{count - 5} more)" : ""
      super(
        "#{count} pending migration(s): #{list}#{suffix}. " \
        "Run 'rake db:migrate' to apply."
      )
    end
  end
end
