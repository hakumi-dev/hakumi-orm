# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    module RailsConfig
      extend T::Sig

      sig { params(config: Configuration, log_level: Symbol).void }
      def self.apply_defaults(config, log_level: :info)
        config.log_level = log_level
        config.models_dir = "app/models" unless config.models_dir
        config.contracts_dir = "app/contracts" unless config.contracts_dir
      end
    end
  end
end
