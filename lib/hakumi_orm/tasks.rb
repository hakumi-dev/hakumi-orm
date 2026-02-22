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

        config = HakumiORM.config
        adapter = config.adapter
        raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

        schema = config.adapter_name == :postgresql ? "public" : nil
        reader = HakumiORM::Codegen::SchemaReader.new(adapter)
        tables = reader.read_tables(schema: schema)

        generator = HakumiORM::Codegen::Generator.new(
          tables,
          dialect: adapter.dialect,
          output_dir: config.output_dir,
          module_name: config.module_name,
          models_dir: config.models_dir,
          contracts_dir: config.contracts_dir
        )
        generator.generate!

        puts "HakumiORM: Generated #{tables.size} table(s) into #{config.output_dir}"
      end
    end
  end
end
