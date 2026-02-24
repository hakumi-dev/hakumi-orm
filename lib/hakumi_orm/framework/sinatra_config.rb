# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    module SinatraConfig
      extend T::Sig

      sig { params(config: Configuration, root: T.nilable(String), log_level: Symbol).void }
      def self.apply_defaults(config, root: nil, log_level: :info)
        config.log_level = log_level

        return unless root

        config.output_dir = "#{root}/db/schema"
        config.migrations_path = "#{root}/db/migrate"
        config.definitions_path = "#{root}/db/definitions.rb"
      end
    end
  end
end
