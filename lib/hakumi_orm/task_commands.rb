# typed: strict
# frozen_string_literal: true

require "digest"
require_relative "task_output"

module HakumiORM
  # Implements the behavior behind rake tasks and CLI task entrypoints.
  module TaskCommands
    extend T::Sig
    include Kernel

    module_function

    INTERNAL_TABLES = %w[hakumi_migrations hakumi_schema_meta].freeze
    FixturesOptions = T.type_alias do
      {
        fixtures_path: String,
        fixtures_dir: T.nilable(String),
        only: T.nilable(T::Array[String]),
        dry_run: T::Boolean,
        verify_fks: T::Boolean
      }
    end

    sig { params(root: String).void }
    def run_install(root:)
      framework = HakumiORM::Framework.current || HakumiORM::Framework.detect
      generator = HakumiORM::SetupGenerator.new(root: root, framework: framework)
      result = generator.run!
      output_port.install_result(result)
    end

    sig { params(name: String).void }
    def run_type_scaffold(name:)
      output_dir = HakumiORM.config.output_dir
      HakumiORM::Codegen::TypeScaffold.generate(name: name, output_dir: output_dir)
      output_port.custom_type_scaffolded(name: name, output_dir: output_dir)
    end

    sig { returns(Migration::Runner) }
    def build_runner
      config = HakumiORM.config
      adapter = configured_adapter!(config)
      HakumiORM.migration_runner_factory_port.build(adapter: adapter, migrations_path: config.migrations_path)
    end

    sig { void }
    def run_generate
      config = HakumiORM.config
      adapter = configured_adapter!(config)

      tables = read_schema(config, adapter)
      defs = HakumiORM::Codegen::DefinitionLoader.load(config.definitions_path)
      custom_assocs = defs[:associations]
      user_enums = defs[:enums]
      table_hooks = defs[:table_hooks]

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
        schema_fingerprint: fingerprint,
        table_hooks: table_hooks
      )
      generator = HakumiORM::Codegen::Generator.new(tables, opts)
      generator.generate!

      HakumiORM::Migration::SchemaFingerprint.store!(adapter, fingerprint, canonical)

      output_port.generated_tables(count: tables.size, output_dir: config.output_dir)
    end

    sig { params(task_prefix: String).void }
    def run_migrate(task_prefix:)
      runner = build_runner
      applied = runner.migrate!
      version = runner.current_version || "none"
      output_port.migrate_result(applied: applied, version: version)
      post_migrate_fingerprint!(task_prefix: task_prefix)
    end

    sig { params(task_prefix: String).void }
    def run_prepare(task_prefix:)
      run_migrate(task_prefix: task_prefix)
    end

    sig { params(count: Integer, task_prefix: String).void }
    def run_rollback(count:, task_prefix:)
      runner = build_runner
      runner.rollback!(count: count)
      output_port.rollback_result(count: count, version: runner.current_version || "none")
      post_migrate_fingerprint!(task_prefix: task_prefix)
    end

    sig { void }
    def show_migration_status
      runner = build_runner
      output_port.migration_status(runner.status)
    end

    sig { void }
    def show_current_version
      runner = build_runner
      output_port.current_version(runner.current_version || "none")
    end

    sig { params(name: String).void }
    def create_migration_file(name:)
      path = HakumiORM.config.migrations_path
      filepath = HakumiORM::Migration::FileGenerator.generate(name: name, path: path)
      output_port.migration_file_created(filepath)
    end

    sig { params(table_name: String).void }
    def run_scaffold(table_name)
      config = HakumiORM.config
      generator = HakumiORM::ScaffoldGenerator.new(table_name, config)
      created = generator.run!

      output_port.scaffold_result(
        table_name: table_name,
        created: created,
        models_dir: config.models_dir,
        contracts_dir: config.contracts_dir
      )
    end

    sig { params(task_prefix: String).void }
    def post_migrate_fingerprint!(task_prefix:)
      Kernel.require "hakumi_orm/codegen"

      config = HakumiORM.config
      adapter = config.adapter
      return unless adapter

      checker = HakumiORM::SchemaDriftChecker.new(config: config, adapter: adapter, internal_tables: INTERNAL_TABLES)
      checker.update_fingerprint!

      if ENV.key?("HAKUMI_SKIP_GENERATE")
        output_port.fingerprint_skip_generate(task_prefix: task_prefix)
        return
      end

      run_generate
    end

    sig { void }
    def run_check
      config = HakumiORM.config
      adapter = configured_adapter!(config)

      Kernel.require "hakumi_orm/codegen"
      checker = HakumiORM::SchemaDriftChecker.new(config: config, adapter: adapter, internal_tables: INTERNAL_TABLES)
      messages = checker.check

      if messages.empty?
        output_port.schema_check_ok
        return
      end

      output_port.schema_check_errors(messages)
      Kernel.exit 1
    end

    sig { void }
    def run_seed
      config = HakumiORM.config
      ensure_generated_loaded_for_seed!(config)
      seed_path = config.seeds_path
      absolute = File.expand_path(seed_path, Dir.pwd)
      unless File.file?(absolute)
        output_port.seed_missing(absolute)
        return
      end

      Kernel.load absolute
      output_port.seed_loaded(absolute)
    end

    sig { void }
    def run_fixtures_load
      config = HakumiORM.config
      adapter = configured_adapter!(config)

      opts = fixtures_options(config)
      absolute = File.expand_path(opts[:fixtures_path], Dir.pwd)
      if opts[:dry_run]
        plan = HakumiORM::Application::FixturesLoad.plan_load!(
          config: config,
          adapter: adapter,
          request: fixtures_request(opts)
        )
        output_port.fixtures_dry_run(
          path: absolute,
          table_count: plan[:table_count],
          row_count: plan[:row_count],
          table_rows: plan[:table_rows]
        )
        return
      end

      loaded_count = HakumiORM::Application::FixturesLoad.load!(
        config: config,
        adapter: adapter,
        request: fixtures_request(opts)
      )
      output_port.fixtures_loaded(path: absolute, table_count: loaded_count)
    end

    sig { params(filter_table: T.nilable(String)).void }
    def list_associations(filter_table = nil)
      config = HakumiORM.config
      adapter = configured_adapter!(config)

      tables = read_schema(config, adapter)
      defs = HakumiORM::Codegen::DefinitionLoader.load(config.definitions_path)
      custom_assocs = defs[:associations]
      opts = HakumiORM::Codegen::GeneratorOptions.new(dialect: adapter.dialect, custom_associations: custom_assocs)
      generator = HakumiORM::Codegen::Generator.new(tables, opts)

      tables.each_value do |table|
        next if filter_table && table.name != filter_table

        ctx = HakumiORM::Codegen::ModelAnnotator.build_cli_context(generator, table, custom_assocs)
        lines = HakumiORM::Codegen::ModelAnnotator.build_assoc_lines_for_cli(ctx)
        next if lines.empty?

        output_port.associations_for_table(table.name, lines)
      end
    end
  end
end
require_relative "task_commands_support"
