# typed: false
# frozen_string_literal: true

require "rake"

module HakumiORM
  module Tasks
    extend Rake::DSL

    namespace :hakumi do
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

      desc "Run pending migrations"
      task :migrate do
        require "hakumi_orm"
        require "hakumi_orm/migration"

        runner = HakumiORM::Tasks.build_runner
        runner.migrate!
        puts "HakumiORM: Migrations complete (version: #{runner.current_version || "none"})"
      end

      desc "Rollback the last migration (usage: rake hakumi:rollback or rake hakumi:rollback[N])"
      task :rollback, [:count] do |_t, args|
        require "hakumi_orm"
        require "hakumi_orm/migration"

        count = (args[:count] || 1).to_i
        runner = HakumiORM::Tasks.build_runner
        runner.rollback!(count: count)
        puts "HakumiORM: Rolled back #{count} migration(s) (version: #{runner.current_version || "none"})"
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

        opts = HakumiORM::Codegen::GeneratorOptions.new(
          dialect: adapter.dialect,
          output_dir: config.output_dir,
          module_name: config.module_name,
          models_dir: config.models_dir,
          contracts_dir: config.contracts_dir
        )
        generator = HakumiORM::Codegen::Generator.new(tables, opts)
        generator.generate!

        puts "HakumiORM: Generated #{tables.size} table(s) into #{config.output_dir}"
      end

      def read_schema(config, adapter)
        case config.adapter_name
        when :postgresql
          HakumiORM::Codegen::SchemaReader.new(adapter).read_tables(schema: "public")
        when :mysql
          schema = config.database
          raise HakumiORM::Error, "config.database is required for MySQL codegen" unless schema

          HakumiORM::Codegen::MysqlSchemaReader.new(adapter).read_tables(schema: schema)
        when :sqlite
          HakumiORM::Codegen::SqliteSchemaReader.new(adapter).read_tables
        else
          raise HakumiORM::Error, "Unknown adapter_name: #{config.adapter_name}"
        end
      end
    end
  end
end
