# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Runs migration "up" and "down" operations with transaction policy and version bookkeeping.
    class Executor
      extend T::Sig

      sig do
        params(
          adapter: Adapter::Base,
          loader: Loader,
          version_store: VersionStore
        ).void
      end
      def initialize(adapter:, loader:, version_store:)
        @adapter = T.let(adapter, Adapter::Base)
        @loader = T.let(loader, Loader)
        @version_store = T.let(version_store, VersionStore)
      end

      sig { params(file_info: FileInfo).void }
      def run_up(file_info)
        klass = @loader.load_migration(file_info)
        migration = klass.new(@adapter)
        if transactional_migration?(klass)
          @adapter.transaction do |_adapter|
            migration.up
            @version_store.record_version(file_info.version, file_info.name)
          end
        else
          log_ddl_warning unless klass.ddl_transaction_disabled?
          migration.up
          @version_store.record_version(file_info.version, file_info.name)
        end
      end

      sig { params(file_info: FileInfo).void }
      def run_down(file_info)
        klass = @loader.load_migration(file_info)
        migration = klass.new(@adapter)
        if transactional_migration?(klass)
          @adapter.transaction do |_adapter|
            migration.down
            @version_store.remove_version(file_info.version)
          end
        else
          log_ddl_warning unless klass.ddl_transaction_disabled?
          migration.down
          @version_store.remove_version(file_info.version)
        end
      end

      private

      sig { params(klass: T.class_of(Migration)).returns(T::Boolean) }
      def transactional_migration?(klass)
        !klass.ddl_transaction_disabled? && @adapter.dialect.supports_ddl_transactions?
      end

      sig { void }
      def log_ddl_warning
        logger = HakumiORM.config.logger
        return unless logger

        logger.warn("HakumiORM: DDL transactions not supported by #{@adapter.dialect.name}. Partial rollback is not guaranteed.")
      end
    end
  end
end
