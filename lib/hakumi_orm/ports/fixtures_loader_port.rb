# typed: strict
# frozen_string_literal: true

require_relative "../fixtures/types"

module HakumiORM
  module Ports
    # Port for fixture loading/planning operations.
    module FixturesLoaderPort
      extend T::Sig
      extend T::Helpers

      interface!

      Request = T.type_alias do
        {
          base_path: String,
          fixtures_dir: T.nilable(String),
          only_names: T.nilable(T::Array[String]),
          verify_foreign_keys: T::Boolean
        }
      end

      sig { abstract.params(config: Configuration, adapter: Adapter::Base, request: Request).returns(Integer) }
      def load!(config:, adapter:, request:); end

      sig do
        abstract
          .params(config: Configuration, adapter: Adapter::Base, request: Request)
          .returns(Fixtures::Types::LoadedFixtures)
      end
      def load_with_data!(config:, adapter:, request:); end

      sig do
        abstract
          .params(config: Configuration, adapter: Adapter::Base, request: Request)
          .returns(Fixtures::Types::LoadPlan)
      end
      def plan_load!(config:, adapter:, request:); end
    end
  end
end
