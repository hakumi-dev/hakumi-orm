# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Ports
    # Port for creating migration runners from adapter/config.
    module MigrationRunnerFactoryPort
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(adapter: Adapter::Base, migrations_path: String).returns(Migration::Runner) }
      def build(adapter:, migrations_path:); end
    end
  end
end
