# typed: false
# frozen_string_literal: true

require "digest"
require "rake"

module HakumiORM
  module Tasks
    extend Rake::DSL

    namespace :hakumi do
      desc "Install HakumiORM (creates config and directory structure)"
      task :install do
        require "hakumi_orm"

        framework = HakumiORM::Framework.current || HakumiORM::Framework.detect
        generator = HakumiORM::SetupGenerator.new(root: Dir.pwd, framework: framework)
        result = generator.run!

        if result[:created].empty?
          puts "HakumiORM: Already installed (all files exist)"
        else
          result[:created].each { |f| puts "  create  #{f}" }
          result[:skipped].each { |f| puts "  exist   #{f}" }
          puts "\nHakumiORM: Installed successfully"
        end
      end

      desc "Generate HakumiORM models from the database schema"
      task :generate do
        require "hakumi_orm"
        require "hakumi_orm/codegen"

        HakumiORM::Tasks.run_generate
      end

      desc "Scaffold a custom type (usage: rake hakumi:type[money])"
      task :type, [:name] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/codegen"

        name = args[:name]
        raise ArgumentError, "Usage: rake hakumi:type[name]" unless name

        output_dir = HakumiORM.config.output_dir || "lib/types"
        HakumiORM::Codegen::TypeScaffold.generate(name: name, output_dir: output_dir)
        puts "HakumiORM: Scaffolded custom type '#{name}' in #{output_dir}"
      end

      desc "Run pending migrations (set HAKUMI_SKIP_GENERATE=1 to skip auto-generate)"
      task :migrate do
        require "hakumi_orm"
        require "hakumi_orm/migration"

        runner = HakumiORM::Tasks.build_runner
        runner.migrate!
        version = runner.current_version || "none"
        puts "HakumiORM: Migrations complete (version: #{version})"

        HakumiORM::Tasks.post_migrate_fingerprint!
      end

      desc "Rollback the last migration (usage: rake hakumi:rollback or rake hakumi:rollback[N])"
      task :rollback, [:count] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/migration"

        count = (args[:count] || 1).to_i
        runner = HakumiORM::Tasks.build_runner
        runner.rollback!(count: count)
        puts "HakumiORM: Rolled back #{count} migration(s) (version: #{runner.current_version || "none"})"

        HakumiORM::Tasks.post_migrate_fingerprint!
      end

      namespace :migrate do
        desc "Show migration status"
        task :status do
          require "hakumi_orm"
          require "hakumi_orm/migration"

          runner = HakumiORM::Tasks.build_runner
          statuses = runner.status
          if statuses.empty?
            puts "No migrations found."
          else
            puts "Status  Version         Name"
            puts "-" * 50
            statuses.each do |entry|
              puts "  #{entry[:status].ljust(6)}#{entry[:version]}  #{entry[:name]}"
            end
          end
        end
      end

      desc "Show current schema version"
      task :version do
        require "hakumi_orm"
        require "hakumi_orm/migration"

        runner = HakumiORM::Tasks.build_runner
        puts "Current version: #{runner.current_version || "none"}"
      end

      desc "Generate a new migration file (usage: rake hakumi:migration[create_users])"
      task :migration, [:name] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/migration"

        name = args[:name]
        raise ArgumentError, "Usage: rake hakumi:migration[name]" unless name

        path = HakumiORM.config.migrations_path
        filepath = HakumiORM::Migration::FileGenerator.generate(name: name, path: path)
        puts "HakumiORM: Created #{filepath}"
      end

      desc "List all associations (usage: rake hakumi:associations or hakumi:associations[users])"
      task :associations, [:table] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/codegen"

        HakumiORM::Tasks.list_associations(args[:table])
      end

      desc "Scaffold model + contract for a table (usage: rake hakumi:scaffold[users])"
      task :scaffold, [:table] do |_t, args|
        require "hakumi_orm"

        table = args[:table]
        raise ArgumentError, "Usage: rake hakumi:scaffold[table_name]" unless table

        HakumiORM::Tasks.run_scaffold(table)
      end

      desc "Check for schema drift between live DB and generated code"
      task :check do
        require "hakumi_orm"
        require "hakumi_orm/codegen"
        require "hakumi_orm/migration"

        HakumiORM::Tasks.run_check
      end
    end

    class << self
      def build_runner
        config = HakumiORM.config
        adapter = config.adapter
        raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

        HakumiORM::Migration::Runner.new(adapter, migrations_path: config.migrations_path)
      end

      def run_generate
        config = HakumiORM.config
        adapter = config.adapter
        raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

        tables = read_schema(config, adapter)
        custom_assocs = HakumiORM::Codegen::AssociationLoader.load(config.associations_path)
        user_enums = HakumiORM::Codegen::EnumLoader.load(config.enums_path)

        user_tables = tables.except(*INTERNAL_TABLES)
        canonical = HakumiORM::Migration::SchemaFingerprint.build_canonical(user_tables)
        fingerprint = Digest::SHA256.hexdigest(canonical)

        opts = HakumiORM::Codegen::GeneratorOptions.new(
          dialect: adapter.dialect,
          output_dir: config.output_dir,
          module_name: config.module_name,
          models_dir: config.models_dir,
          contracts_dir: config.contracts_dir,
          custom_associations: custom_assocs,
          user_enums: user_enums,
          internal_tables: INTERNAL_TABLES,
          schema_fingerprint: fingerprint
        )
        generator = HakumiORM::Codegen::Generator.new(tables, opts)
        generator.generate!

        HakumiORM::Migration::SchemaFingerprint.store!(adapter, fingerprint, canonical)

        puts "HakumiORM: Generated #{tables.size} table(s) into #{config.output_dir}"
      end

      def run_scaffold(table_name)
        config = HakumiORM.config
        generator = HakumiORM::ScaffoldGenerator.new(table_name, config)
        created = generator.run!

        if created.empty?
          if config.models_dir.nil? && config.contracts_dir.nil?
            puts "HakumiORM: Set config.models_dir and/or config.contracts_dir to scaffold files."
          else
            puts "HakumiORM: All files already exist for '#{table_name}'."
          end
        else
          created.each { |f| puts "  create  #{f}" }
        end
      end

      def post_migrate_fingerprint!
        require "hakumi_orm/codegen"

        config = HakumiORM.config
        adapter = config.adapter
        return unless adapter

        checker = HakumiORM::SchemaDriftChecker.new(adapter, internal_tables: INTERNAL_TABLES)
        checker.update_fingerprint!

        if ENV.key?("HAKUMI_SKIP_GENERATE")
          puts "HakumiORM: Fingerprint updated. Skipping auto-generate (HAKUMI_SKIP_GENERATE)."
          puts "  Run 'rake hakumi:generate' to update generated code."
          return
        end

        run_generate
      end

      def run_check
        config = HakumiORM.config
        adapter = config.adapter
        raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

        require "hakumi_orm/codegen"
        checker = HakumiORM::SchemaDriftChecker.new(adapter, internal_tables: INTERNAL_TABLES)
        messages = checker.check

        if messages.empty?
          puts "HakumiORM: Schema is in sync. No drift detected."
          return
        end

        messages.each { |l| warn "HakumiORM: #{l}" }
        exit 1
      end

      def list_associations(filter_table = nil)
        config = HakumiORM.config
        adapter = config.adapter
        raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

        tables = read_schema(config, adapter)
        custom_assocs = HakumiORM::Codegen::AssociationLoader.load(config.associations_path)
        opts = HakumiORM::Codegen::GeneratorOptions.new(dialect: adapter.dialect, custom_associations: custom_assocs)
        generator = HakumiORM::Codegen::Generator.new(tables, opts)

        tables.each_value do |table|
          next if filter_table && table.name != filter_table

          ctx = HakumiORM::Codegen::ModelAnnotator.build_cli_context(generator, table, custom_assocs)
          lines = HakumiORM::Codegen::ModelAnnotator.send(:build_assoc_lines_for_cli, ctx)
          next if lines.empty?

          puts "\n#{table.name}"
          lines.each { |l| puts l }
        end
      end

      INTERNAL_TABLES = %w[hakumi_migrations hakumi_schema_meta].freeze

      def read_schema(config, adapter)
        HakumiORM::SchemaDriftChecker.read_schema(config, adapter)
      end
    end
  end
end
