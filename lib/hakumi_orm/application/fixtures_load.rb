# typed: strict
# frozen_string_literal: true

require_relative "../fixtures/loader"

module HakumiORM
  module Application
    # Public application operation for fixture planning/loading.
    class FixturesLoad
      extend T::Sig

      Request = T.type_alias do
        {
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String]),
          verify_foreign_keys: T::Boolean
        }
      end

      sig do
        params(
          config: Configuration,
          adapter: Adapter::Base,
          request: Request
        ).returns(Integer)
      end
      def self.load!(config:, adapter:, request:)
        loader = build_loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys])
        loader.load!(base_path: request[:base_path], fixtures_dir: request[:fixtures_dir], only_names: request[:only_names])
      end

      sig do
        params(
          config: Configuration,
          adapter: Adapter::Base,
          request: Request
        ).returns(Fixtures::Loader::LoadedFixtures)
      end
      def self.load_with_data!(config:, adapter:, request:)
        loader = build_loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys])
        loader.load_with_data!(
          base_path: request[:base_path],
          fixtures_dir: request[:fixtures_dir],
          only_names: request[:only_names]
        )
      end

      sig do
        params(
          config: Configuration,
          adapter: Adapter::Base,
          request: Request
        ).returns(Fixtures::Loader::LoadPlan)
      end
      def self.plan_load!(config:, adapter:, request:)
        loader = build_loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys])
        loader.plan_load!(base_path: request[:base_path], fixtures_dir: request[:fixtures_dir], only_names: request[:only_names])
      end

      sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
      def self.read_tables(config:, adapter:)
        SchemaIntrospection.read_tables(config, adapter)
      end

      sig do
        params(config: Configuration, adapter: Adapter::Base, verify_foreign_keys: T::Boolean).returns(Fixtures::Loader)
      end
      def self.build_loader(config:, adapter:, verify_foreign_keys:)
        tables = read_tables(config: config, adapter: adapter)
        Fixtures::Loader.new(
          adapter: adapter,
          tables: tables,
          verify_foreign_keys: verify_foreign_keys
        )
      end
      private_class_method :build_loader
    end
  end
end
