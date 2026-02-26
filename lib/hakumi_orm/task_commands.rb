# typed: false
# frozen_string_literal: true

require "digest"
require_relative "task_output"

module HakumiORM
  module TaskCommands
    module_function

    INTERNAL_TABLES = %w[hakumi_migrations hakumi_schema_meta].freeze

    def run_install(root:)
      framework = HakumiORM::Framework.current || HakumiORM::Framework.detect
      generator = HakumiORM::SetupGenerator.new(root: root, framework: framework)
      result = generator.run!
      HakumiORM::TaskOutput.install_result(result)
    end

    def run_type_scaffold(name:)
      output_dir = HakumiORM.config.output_dir || "lib/types"
      HakumiORM::Codegen::TypeScaffold.generate(name: name, output_dir: output_dir)
      HakumiORM::TaskOutput.custom_type_scaffolded(name: name, output_dir: output_dir)
    end

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
      defs = HakumiORM::Codegen::DefinitionLoader.load(config.definitions_path)
      custom_assocs = defs[:associations]
      user_enums = defs[:enums]

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

      HakumiORM::TaskOutput.generated_tables(count: tables.size, output_dir: config.output_dir)
    end

    def run_migrate(task_prefix:)
      runner = build_runner
      applied = runner.migrate!
      version = runner.current_version || "none"
      HakumiORM::TaskOutput.migrate_result(applied: applied, version: version)
      post_migrate_fingerprint!(task_prefix: task_prefix)
    end

    def run_rollback(count:, task_prefix:)
      runner = build_runner
      runner.rollback!(count: count)
      HakumiORM::TaskOutput.rollback_result(count: count, version: runner.current_version || "none")
      post_migrate_fingerprint!(task_prefix: task_prefix)
    end

    def show_migration_status
      runner = build_runner
      HakumiORM::TaskOutput.migration_status(runner.status)
    end

    def show_current_version
      runner = build_runner
      HakumiORM::TaskOutput.current_version(runner.current_version || "none")
    end

    def create_migration_file(name:)
      path = HakumiORM.config.migrations_path
      filepath = HakumiORM::Migration::FileGenerator.generate(name: name, path: path)
      HakumiORM::TaskOutput.migration_file_created(filepath)
    end

    def run_scaffold(table_name)
      config = HakumiORM.config
      generator = HakumiORM::ScaffoldGenerator.new(table_name, config)
      created = generator.run!

      HakumiORM::TaskOutput.scaffold_result(
        table_name: table_name,
        created: created,
        models_dir: config.models_dir,
        contracts_dir: config.contracts_dir
      )
    end

    def post_migrate_fingerprint!(task_prefix:)
      require "hakumi_orm/codegen"

      config = HakumiORM.config
      adapter = config.adapter
      return unless adapter

      checker = HakumiORM::SchemaDriftChecker.new(adapter, internal_tables: INTERNAL_TABLES)
      checker.update_fingerprint!

      if ENV.key?("HAKUMI_SKIP_GENERATE")
        HakumiORM::TaskOutput.fingerprint_skip_generate(task_prefix: task_prefix)
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
        HakumiORM::TaskOutput.schema_check_ok
        return
      end

      HakumiORM::TaskOutput.schema_check_errors(messages)
      exit 1
    end

    def list_associations(filter_table = nil)
      config = HakumiORM.config
      adapter = config.adapter
      raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

      tables = read_schema(config, adapter)
      defs = HakumiORM::Codegen::DefinitionLoader.load(config.definitions_path)
      custom_assocs = defs[:associations]
      opts = HakumiORM::Codegen::GeneratorOptions.new(dialect: adapter.dialect, custom_associations: custom_assocs)
      generator = HakumiORM::Codegen::Generator.new(tables, opts)

      tables.each_value do |table|
        next if filter_table && table.name != filter_table

        ctx = HakumiORM::Codegen::ModelAnnotator.build_cli_context(generator, table, custom_assocs)
        lines = HakumiORM::Codegen::ModelAnnotator.send(:build_assoc_lines_for_cli, ctx)
        next if lines.empty?

        HakumiORM::TaskOutput.associations_for_table(table.name, lines)
      end
    end

    def read_schema(config, adapter)
      HakumiORM::SchemaDriftChecker.read_schema(config, adapter)
    end
  end
end
