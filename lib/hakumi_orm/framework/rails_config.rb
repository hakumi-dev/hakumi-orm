# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    module RailsConfig
      extend T::Sig

      sig { params(config: Configuration, logger: T.nilable(::Logger)).void }
      def self.apply_defaults(config, logger: nil)
        config.logger = logger
        config.models_dir = "app/models" unless config.models_dir
        config.contracts_dir = "app/contracts" unless config.contracts_dir
      end
    end
  end
end
