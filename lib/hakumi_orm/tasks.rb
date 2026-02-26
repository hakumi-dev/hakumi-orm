# typed: false
# frozen_string_literal: true

require "rake"
require_relative "task_commands"
require_relative "task_output"
require_relative "tasks_compat"

module HakumiORM
  module Tasks
    extend Rake::DSL

    def self.safe_define_task(task_name)
      return if Rake::Task.task_defined?(task_name)

      yield
    end

    def self.task_prefix = "db:"

    namespace :db do
      desc "Install HakumiORM (creates config and directory structure)"
      task :install do
        require "hakumi_orm"

        framework = HakumiORM::Framework.current || HakumiORM::Framework.detect
        generator = HakumiORM::SetupGenerator.new(root: Dir.pwd, framework: framework)
        result = generator.run!
        HakumiORM::TaskOutput.install_result(result)
      end

      desc "Generate HakumiORM models from the database schema"
      task :generate do
        require "hakumi_orm"
        require "hakumi_orm/codegen"
        require "hakumi_orm/migration"

        HakumiORM::TaskCommands.run_generate
      end

      desc "Scaffold a custom type (usage: rake #{HakumiORM::Tasks.task_prefix}type[money])"
      task :type, [:name] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/codegen"

        name = args[:name]
        raise ArgumentError, "Usage: rake #{HakumiORM::Tasks.task_prefix}type[name]" unless name

        output_dir = HakumiORM.config.output_dir || "lib/types"
        HakumiORM::Codegen::TypeScaffold.generate(name: name, output_dir: output_dir)
        HakumiORM::TaskOutput.custom_type_scaffolded(name: name, output_dir: output_dir)
      end

      desc "Run pending migrations (set HAKUMI_SKIP_GENERATE=1 to skip auto-generate)"
      task :migrate do
        require "hakumi_orm"
        require "hakumi_orm/migration"

        runner = HakumiORM::TaskCommands.build_runner
        applied = runner.migrate!
        version = runner.current_version || "none"
        HakumiORM::TaskOutput.migrate_result(applied: applied, version: version)

        HakumiORM::TaskCommands.post_migrate_fingerprint!(task_prefix: HakumiORM::Tasks.task_prefix)
      end

      desc "Rollback the last migration (usage: rake #{HakumiORM::Tasks.task_prefix}rollback or rake #{HakumiORM::Tasks.task_prefix}rollback[N])"
      task :rollback, [:count] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/migration"

        count = (args[:count] || 1).to_i
        runner = HakumiORM::TaskCommands.build_runner
        runner.rollback!(count: count)
        HakumiORM::TaskOutput.rollback_result(count: count, version: runner.current_version || "none")

        HakumiORM::TaskCommands.post_migrate_fingerprint!(task_prefix: HakumiORM::Tasks.task_prefix)
      end

      namespace :migrate do
        desc "Show migration status"
        task :status do
          require "hakumi_orm"
          require "hakumi_orm/migration"

          runner = HakumiORM::TaskCommands.build_runner
          statuses = runner.status
          HakumiORM::TaskOutput.migration_status(statuses)
        end
      end

      desc "Show current schema version"
      task :version do
        require "hakumi_orm"
        require "hakumi_orm/migration"

        runner = HakumiORM::TaskCommands.build_runner
        HakumiORM::TaskOutput.current_version(runner.current_version || "none")
      end

      desc "Generate a new migration file (usage: rake #{HakumiORM::Tasks.task_prefix}migration[create_users])"
      task :migration, [:name] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/migration"

        name = args[:name]
        raise ArgumentError, "Usage: rake #{HakumiORM::Tasks.task_prefix}migration[name]" unless name

        path = HakumiORM.config.migrations_path
        filepath = HakumiORM::Migration::FileGenerator.generate(name: name, path: path)
        HakumiORM::TaskOutput.migration_file_created(filepath)
      end

      desc "List all associations (usage: rake #{HakumiORM::Tasks.task_prefix}associations or #{HakumiORM::Tasks.task_prefix}associations[users])"
      task :associations, [:table] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/codegen"

        HakumiORM::TaskCommands.list_associations(args[:table])
      end

      desc "Scaffold model + contract for a table (usage: rake #{HakumiORM::Tasks.task_prefix}scaffold[users])"
      task :scaffold, [:table] do |_t, args|
        require "hakumi_orm"

        table = args[:table]
        raise ArgumentError, "Usage: rake #{HakumiORM::Tasks.task_prefix}scaffold[table_name]" unless table

        HakumiORM::TaskCommands.run_scaffold(table)
      end

      desc "Check for schema drift between live DB and generated code"
      task :check do
        require "hakumi_orm"
        require "hakumi_orm/codegen"
        require "hakumi_orm/migration"

        HakumiORM::TaskCommands.run_check
      end
    end
  end
end

HakumiORM::TasksCompat.define!(HakumiORM::Tasks)
