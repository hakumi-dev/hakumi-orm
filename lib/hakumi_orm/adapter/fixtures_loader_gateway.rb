# typed: strict
# frozen_string_literal: true

require_relative "../internal"

module HakumiORM
  module Adapter
    # Infrastructure implementation of FixturesLoaderPort.
    class FixturesLoaderGateway
      include Ports::FixturesLoaderPort

      extend T::Sig

      sig { override.params(config: Configuration, adapter: Adapter::Base, request: Ports::FixturesLoaderPort::Request).returns(Integer) }
      def load!(config:, adapter:, request:)
        loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys]).load!(
          base_path: request[:base_path],
          fixtures_dir: request[:fixtures_dir],
          only_names: request[:only_names]
        )
      end

      sig do
        override
          .params(config: Configuration, adapter: Adapter::Base, request: Ports::FixturesLoaderPort::Request)
          .returns(Fixtures::Types::LoadedFixtures)
      end
      def load_with_data!(config:, adapter:, request:)
        loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys]).load_with_data!(
          base_path: request[:base_path],
          fixtures_dir: request[:fixtures_dir],
          only_names: request[:only_names]
        )
      end

      sig do
        override
          .params(config: Configuration, adapter: Adapter::Base, request: Ports::FixturesLoaderPort::Request)
          .returns(Fixtures::Types::LoadPlan)
      end
      def plan_load!(config:, adapter:, request:)
        loader(config: config, adapter: adapter, verify_foreign_keys: request[:verify_foreign_keys]).plan_load!(
          base_path: request[:base_path],
          fixtures_dir: request[:fixtures_dir],
          only_names: request[:only_names]
        )
      end

      private

      sig { params(config: Configuration, adapter: Adapter::Base, verify_foreign_keys: T::Boolean).returns(Internal::FixturesLoader) }
      def loader(config:, adapter:, verify_foreign_keys:)
        tables = Application::SchemaIntrospection.read_tables(config, adapter)
        Internal::FixturesLoader.new(
          adapter: adapter,
          tables: tables,
          verify_foreign_keys: verify_foreign_keys
        )
      end
    end
  end
end
