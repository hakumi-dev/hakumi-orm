# typed: strict
# frozen_string_literal: true

require_relative "../fixtures/types"

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
        HakumiORM.fixtures_loader_port.load!(config: config, adapter: adapter, request: request)
      end

      sig do
        params(
          config: Configuration,
          adapter: Adapter::Base,
          request: Request
        ).returns(Fixtures::Types::LoadedFixtures)
      end
      def self.load_with_data!(config:, adapter:, request:)
        HakumiORM.fixtures_loader_port.load_with_data!(config: config, adapter: adapter, request: request)
      end

      sig do
        params(
          config: Configuration,
          adapter: Adapter::Base,
          request: Request
        ).returns(Fixtures::Types::LoadPlan)
      end
      def self.plan_load!(config:, adapter:, request:)
        HakumiORM.fixtures_loader_port.plan_load!(config: config, adapter: adapter, request: request)
      end

      sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
      def self.read_tables(config:, adapter:)
        SchemaIntrospection.read_tables(config, adapter)
      end
    end
  end
end
