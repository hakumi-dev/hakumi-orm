# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Support methods extracted from TaskCommands to keep orchestration concise.
  module TaskCommands
    extend T::Sig
    include Kernel

    module_function

    sig { params(config: Configuration).returns(FixturesOptions) }
    def fixtures_options(config)
      raw_only = ENV.fetch("FIXTURES", nil)
      only = raw_only ? raw_only.split(",").map(&:strip).reject(&:empty?) : nil
      {
        fixtures_path: ENV.fetch("FIXTURES_PATH", config.fixtures_path),
        fixtures_dir: ENV.fetch("FIXTURES_DIR", nil),
        only: only,
        dry_run: ENV["HAKUMI_FIXTURES_DRY_RUN"] == "1",
        verify_fks: config.verify_foreign_keys_for_fixtures || ENV["HAKUMI_VERIFY_FIXTURE_FKS"] == "1"
      }
    end

    sig { params(opts: FixturesOptions).returns(Ports::FixturesLoaderPort::Request) }
    def fixtures_request(opts)
      {
        base_path: opts[:fixtures_path],
        fixtures_dir: opts[:fixtures_dir],
        only_names: opts[:only],
        verify_foreign_keys: opts[:verify_fks]
      }
    end

    sig { params(config: Configuration).void }
    def ensure_generated_loaded_for_seed!(config)
      manifest = File.expand_path(File.join(config.output_dir, "manifest.rb"), Dir.pwd)
      Kernel.require manifest if File.file?(manifest)

      [config.models_dir, config.contracts_dir].compact.each do |dir|
        root = File.expand_path(dir, Dir.pwd)
        next unless Dir.exist?(root)

        Dir[File.join(root, "**", "*.rb")].each { |file| Kernel.require file }
      end
    end

    sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
    def read_schema(config, adapter)
      HakumiORM::Application::SchemaIntrospection.read_tables(config, adapter)
    end

    sig { returns(Ports::TaskOutputPort) }
    def output_port
      HakumiORM.task_output_port
    end

    sig { params(config: Configuration).returns(Adapter::Base) }
    def configured_adapter!(config)
      adapter = config.adapter
      Kernel.raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter
      adapter
    end
  end
end
