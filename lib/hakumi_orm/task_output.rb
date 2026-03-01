# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Centralizes task output formatting for the console.
  module TaskOutput
    extend T::Sig
    include Kernel

    module_function

    sig { params(result: T::Hash[Symbol, T::Array[String]]).void }
    def install_result(result)
      created = result.fetch(:created, [])
      skipped = result.fetch(:skipped, [])
      if created.empty?
        puts "HakumiORM: Already installed (all files exist)"
        return
      end

      created.each { |path| puts "  create  #{path}" }
      skipped.each { |path| puts "  exist   #{path}" }
      puts "\nHakumiORM: Installed successfully"
    end

    sig { params(count: Integer, output_dir: String).void }
    def generated_tables(count:, output_dir:)
      puts "HakumiORM: Generated #{count} table(s) into #{output_dir}"
    end

    sig { params(name: String, output_dir: String).void }
    def custom_type_scaffolded(name:, output_dir:)
      puts "HakumiORM: Scaffolded custom type '#{name}' in #{output_dir}"
    end

    sig { params(applied: T::Array[Migration::FileInfo], version: String).void }
    def migrate_result(applied:, version:)
      if applied.empty?
        puts "HakumiORM: No pending migrations (version: #{version})"
        return
      end

      puts "HakumiORM: Applied #{applied.length} migration(s):"
      applied.each { |migration| puts "  up  #{migration.version}  #{migration.name}" }
      puts "HakumiORM: Migrations complete (version: #{version})"
    end

    sig { params(count: Integer, version: String).void }
    def rollback_result(count:, version:)
      puts "HakumiORM: Rolled back #{count} migration(s) (version: #{version})"
    end

    sig { params(statuses: T::Array[T::Hash[Symbol, String]]).void }
    def migration_status(statuses)
      if statuses.empty?
        puts "No migrations found."
        return
      end

      puts "Status  Version         Name"
      puts "-" * 50
      statuses.each do |entry|
        status = entry.fetch(:status)
        version = entry.fetch(:version)
        name = entry.fetch(:name)
        puts "  #{status.ljust(6)}#{version}  #{name}"
      end
    end

    sig { params(version: String).void }
    def current_version(version)
      puts "Current version: #{version}"
    end

    sig { params(filepath: String).void }
    def migration_file_created(filepath)
      puts "HakumiORM: Created #{filepath}"
    end

    sig do
      params(table_name: String, created: T::Array[String], models_dir: T.nilable(String), contracts_dir: T.nilable(String)).void
    end
    def scaffold_result(table_name:, created:, models_dir:, contracts_dir:)
      if created.empty?
        if models_dir.nil? && contracts_dir.nil?
          puts "HakumiORM: Set config.models_dir and/or config.contracts_dir to scaffold files."
        else
          puts "HakumiORM: All files already exist for '#{table_name}'."
        end
        return
      end

      created.each { |path| puts "  create  #{path}" }
    end

    sig { params(task_prefix: String).void }
    def fingerprint_skip_generate(task_prefix:)
      puts "HakumiORM: Fingerprint updated. Skipping auto-generate (HAKUMI_SKIP_GENERATE)."
      puts "  Run 'rake #{task_prefix}generate' to update generated code."
    end

    sig { void }
    def schema_check_ok
      puts "HakumiORM: Schema is in sync. No drift detected."
    end

    sig { params(messages: T::Array[String]).void }
    def schema_check_errors(messages)
      messages.each { |line| warn "HakumiORM: #{line}" }
    end

    sig { params(path: String).void }
    def seed_missing(path)
      warn "HakumiORM: Seed file not found at #{path}"
    end

    sig { params(path: String).void }
    def seed_loaded(path)
      puts "HakumiORM: Seed completed from #{path}"
    end

    sig { params(path: String, table_count: Integer).void }
    def fixtures_loaded(path:, table_count:)
      puts "HakumiORM: Loaded fixtures from #{path} (#{table_count} table(s))"
    end

    sig { params(path: String, table_count: Integer, row_count: Integer, table_rows: T::Hash[String, Integer]).void }
    def fixtures_dry_run(path:, table_count:, row_count:, table_rows:)
      puts "HakumiORM: Fixtures dry-run from #{path} (#{table_count} table(s), #{row_count} row(s))"
      table_rows.sort.each do |table_name, count|
        puts "  - #{table_name}: #{count} row(s)"
      end
    end

    sig { params(table_name: String, lines: T::Array[String]).void }
    def associations_for_table(table_name, lines)
      puts "\n#{table_name}"
      lines.each { |line| puts line }
    end
  end
end
