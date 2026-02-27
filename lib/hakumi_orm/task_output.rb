# typed: false
# frozen_string_literal: true

module HakumiORM
  module TaskOutput
    module_function

    def install_result(result)
      if result[:created].empty?
        puts "HakumiORM: Already installed (all files exist)"
        return
      end

      result[:created].each { |path| puts "  create  #{path}" }
      result[:skipped].each { |path| puts "  exist   #{path}" }
      puts "\nHakumiORM: Installed successfully"
    end

    def generated_tables(count:, output_dir:)
      puts "HakumiORM: Generated #{count} table(s) into #{output_dir}"
    end

    def custom_type_scaffolded(name:, output_dir:)
      puts "HakumiORM: Scaffolded custom type '#{name}' in #{output_dir}"
    end

    def migrate_result(applied:, version:)
      if applied.empty?
        puts "HakumiORM: No pending migrations (version: #{version})"
        return
      end

      puts "HakumiORM: Applied #{applied.length} migration(s):"
      applied.each { |migration| puts "  up  #{migration.version}  #{migration.name}" }
      puts "HakumiORM: Migrations complete (version: #{version})"
    end

    def rollback_result(count:, version:)
      puts "HakumiORM: Rolled back #{count} migration(s) (version: #{version})"
    end

    def migration_status(statuses)
      if statuses.empty?
        puts "No migrations found."
        return
      end

      puts "Status  Version         Name"
      puts "-" * 50
      statuses.each do |entry|
        puts "  #{entry[:status].ljust(6)}#{entry[:version]}  #{entry[:name]}"
      end
    end

    def current_version(version)
      puts "Current version: #{version}"
    end

    def migration_file_created(filepath)
      puts "HakumiORM: Created #{filepath}"
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

    def fingerprint_skip_generate(task_prefix:)
      puts "HakumiORM: Fingerprint updated. Skipping auto-generate (HAKUMI_SKIP_GENERATE)."
      puts "  Run 'rake #{task_prefix}generate' to update generated code."
    end

    def schema_check_ok
      puts "HakumiORM: Schema is in sync. No drift detected."
    end

    def schema_check_errors(messages)
      messages.each { |line| warn "HakumiORM: #{line}" }
    end

    def seed_missing(path)
      warn "HakumiORM: Seed file not found at #{path}"
    end

    def seed_loaded(path)
      puts "HakumiORM: Seed completed from #{path}"
    end

    def associations_for_table(table_name, lines)
      puts "\n#{table_name}"
      lines.each { |line| puts line }
    end
  end
end
