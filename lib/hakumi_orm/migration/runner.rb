# typed: strict
# frozen_string_literal: true

# Internal component for migration/runner.
module HakumiORM
  class Migration
    # Internal class for HakumiORM.
    class Runner
      extend T::Sig

      sig { params(adapter: Adapter::Base, migrations_path: String).void }
      def initialize(adapter, migrations_path: "db/migrate")
        @adapter = T.let(adapter, Adapter::Base)
        @migrations_path = T.let(migrations_path, String)
        @migration_loader = T.let(Loader.new(migrations_path), Loader)
        @migration_lock = T.let(Lock.new(adapter), Lock)
        @version_store = T.let(VersionStore.new(adapter), VersionStore)
        @migration_executor = T.let(
          Executor.new(adapter: adapter, loader: @migration_loader, version_store: @version_store),
          Executor
        )
      end

      sig { returns(T::Array[Migration::FileInfo]) }
      def migrate!
        applied_now = T.let([], T::Array[Migration::FileInfo])
        with_advisory_lock do
          ensure_table!
          applied = applied_versions
          pending_files = migration_files.reject { |f| applied.include?(f.version) }

          pending_files.each do |file_info|
            run_up(file_info)
            applied_now << file_info
          end
        end
        applied_now
      end

      sig { params(count: Integer).void }
      def rollback!(count: 1)
        with_advisory_lock do
          ensure_table!
          applied = applied_versions.sort.reverse
          versions_to_rollback = applied.first(count)

          files_by_version = T.let({}, T::Hash[String, Migration::FileInfo])
          migration_files.each { |f| files_by_version[f.version] = f }

          versions_to_rollback.each do |version|
            file_info = files_by_version[version]
            next unless file_info

            run_down(file_info)
          end
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def status
        ensure_table!
        applied = applied_versions

        migration_files.map do |file_info|
          {
            status: applied.include?(file_info.version) ? "up" : "down",
            version: file_info.version,
            name: file_info.name
          }
        end
      end

      sig { returns(T.nilable(String)) }
      def current_version
        ensure_table!
        applied_versions.max
      end

      private

      sig { void }
      def ensure_table!
        @version_store.ensure_table!
      end

      sig { returns(T::Array[String]) }
      def applied_versions
        @version_store.applied_versions
      end

      sig { returns(T::Array[Migration::FileInfo]) }
      def migration_files
        @migration_loader.migration_files
      end

      sig { params(file_info: Migration::FileInfo).void }
      def run_up(file_info)
        @migration_executor.run_up(file_info)
      end

      sig { params(file_info: Migration::FileInfo).void }
      def run_down(file_info)
        @migration_executor.run_down(file_info)
      end

      sig { params(blk: T.proc.void).void }
      def with_advisory_lock(&blk)
        @migration_lock.with_advisory_lock(&blk)
      end
    end
  end
end
