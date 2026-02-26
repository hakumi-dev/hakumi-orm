# typed: false
# frozen_string_literal: true

require "digest"

module HakumiORM
  module TaskCommands
    module_function

    INTERNAL_TABLES = %w[hakumi_migrations hakumi_schema_meta].freeze

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

    def post_migrate_fingerprint!(task_prefix:)
      require "hakumi_orm/codegen"

      config = HakumiORM.config
      adapter = config.adapter
      return unless adapter

      checker = HakumiORM::SchemaDriftChecker.new(adapter, internal_tables: INTERNAL_TABLES)
      checker.update_fingerprint!

      if ENV.key?("HAKUMI_SKIP_GENERATE")
        puts "HakumiORM: Fingerprint updated. Skipping auto-generate (HAKUMI_SKIP_GENERATE)."
        puts "  Run 'rake #{task_prefix}generate' to update generated code."
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

      messages.each { |line| warn "HakumiORM: #{line}" }
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

        puts "\n#{table.name}"
        lines.each { |line| puts line }
      end
    end

    def read_schema(config, adapter)
      HakumiORM::SchemaDriftChecker.read_schema(config, adapter)
    end
  end
end
