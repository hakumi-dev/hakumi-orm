# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
    # Infrastructure implementation of MigrationRunnerFactoryPort.
    class MigrationRunnerFactoryGateway
      include Ports::MigrationRunnerFactoryPort

      extend T::Sig

      sig { override.params(adapter: Adapter::Base, migrations_path: String).returns(Migration::Runner) }
      def build(adapter:, migrations_path:)
        Migration::Runner.new(adapter, migrations_path: migrations_path)
      end
    end
  end
end
