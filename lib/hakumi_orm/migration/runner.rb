# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    class Runner
      extend T::Sig

      class FileInfo < T::Struct
        const :version, String
        const :name, String
        const :filename, String
      end

      MIGRATION_FILE_PATTERN = T.let(/\A(\d{14})_(\w+)\.rb\z/, Regexp)

      CREATE_TABLE_SQL = T.let(<<~SQL, String)
        CREATE TABLE IF NOT EXISTS hakumi_migrations (
          version varchar(14) PRIMARY KEY,
          name varchar(255) NOT NULL,
          migrated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      sig { params(adapter: Adapter::Base, migrations_path: String).void }
      def initialize(adapter, migrations_path: "db/migrate")
        @adapter = T.let(adapter, Adapter::Base)
        @migrations_path = T.let(migrations_path, String)
      end

      sig { void }
      def migrate!
        with_advisory_lock do
          ensure_table!
          applied = applied_versions
          pending_files = migration_files.reject { |f| applied.include?(f.version) }

          pending_files.each do |file_info|
            run_up(file_info)
          end
        end
      end

      sig { params(count: Integer).void }
      def rollback!(count: 1)
        with_advisory_lock do
          ensure_table!
          applied = applied_versions.sort.reverse
          versions_to_rollback = applied.first(count)

          files_by_version = T.let({}, T::Hash[String, FileInfo])
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
        @adapter.exec(CREATE_TABLE_SQL)
      end

      sig { returns(T::Array[String]) }
      def applied_versions
        result = @adapter.exec("SELECT version FROM hakumi_migrations ORDER BY version")
        versions = T.let([], T::Array[String])
        i = T.let(0, Integer)
        while i < result.row_count
          versions << result.fetch_value(i, 0)
          i += 1
        end
        result.close
        versions
      end

      sig { returns(T::Array[FileInfo]) }
      def migration_files
        return [] unless Dir.exist?(@migrations_path)

        Dir.children(@migrations_path).grep(MIGRATION_FILE_PATTERN).sort.filter_map do |filename|
          match = filename.match(MIGRATION_FILE_PATTERN)
          next unless match

          version = match[1]
          next unless version

          name = filename.delete_suffix(".rb").sub(/\A\d{14}_/, "")
          FileInfo.new(version: version, name: name, filename: filename)
        end
      end

      sig { params(file_info: FileInfo).void }
      def run_up(file_info)
        klass = load_migration(file_info)
        migration = klass.new(@adapter)
        wrap_in_transaction(klass) { migration.up }
        record_version(file_info.version, file_info.name)
      end

      sig { params(file_info: FileInfo).void }
      def run_down(file_info)
        klass = load_migration(file_info)
        migration = klass.new(@adapter)
        wrap_in_transaction(klass) { migration.down }
        remove_version(file_info.version)
      end

      sig { params(klass: T.class_of(Migration), blk: T.proc.void).void }
      def wrap_in_transaction(klass, &blk)
        if klass.ddl_transaction_disabled? || !@adapter.dialect.supports_ddl_transactions?
          log_ddl_warning unless klass.ddl_transaction_disabled?
          blk.call
        else
          @adapter.transaction { |_adapter| blk.call }
        end
      end

      sig { params(blk: T.proc.void).void }
      def with_advisory_lock(&blk)
        dialect = @adapter.dialect
        unless dialect.supports_advisory_lock?
          blk.call
          return
        end

        lock_sql = dialect.advisory_lock_sql
        unlock_sql = dialect.advisory_unlock_sql
        @adapter.exec(lock_sql) if lock_sql
        begin
          blk.call
        ensure
          @adapter.exec(unlock_sql) if unlock_sql
        end
      end

      sig { void }
      def log_ddl_warning
        logger = HakumiORM.config.logger
        return unless logger

        logger.warn("HakumiORM: DDL transactions not supported by #{@adapter.dialect.name}. Partial rollback is not guaranteed.")
      end

      sig { params(file_info: FileInfo).returns(T.class_of(Migration)) }
      def load_migration(file_info)
        path = File.join(@migrations_path, file_info.filename)
        class_name = file_info.name.split("_").map(&:capitalize).join

        begin
          load path
        rescue SyntaxError, LoadError => e
          raise HakumiORM::Error, "Failed to load migration #{file_info.filename}: #{e.message}"
        end

        begin
          klass = Object.const_get(class_name) # rubocop:disable Sorbet/ConstantsFromStrings
        rescue NameError
          raise HakumiORM::Error,
                "Migration #{file_info.filename} must define class #{class_name} (expected from filename)"
        end

        raise HakumiORM::Error, "#{class_name} must inherit from HakumiORM::Migration" unless klass < Migration

        klass
      end

      sig { params(version: String, name: String).void }
      def record_version(version, name)
        safe_version = version.gsub("'", "''")
        safe_name = name.gsub("'", "''")
        @adapter.exec("INSERT INTO hakumi_migrations (version, name) VALUES ('#{safe_version}', '#{safe_name}')")
      end

      sig { params(version: String).void }
      def remove_version(version)
        safe_version = version.gsub("'", "''")
        @adapter.exec("DELETE FROM hakumi_migrations WHERE version = '#{safe_version}'")
      end
    end
  end
end
