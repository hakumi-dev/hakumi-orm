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
    end

    class << self
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
