# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    module SinatraConfig
      extend T::Sig

      sig { params(config: Configuration, root: T.nilable(String), logger: T.nilable(::Logger)).void }
      def self.apply_defaults(config, root: nil, logger: nil)
        config.logger = logger if logger

        return unless root

        config.output_dir = "#{root}/db/generated"
        config.migrations_path = "#{root}/db/migrate"
        config.associations_path = "#{root}/db/associations"
      end
    end
  end
end
