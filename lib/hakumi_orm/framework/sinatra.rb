# typed: false
# frozen_string_literal: true

require_relative "sinatra_config"

module HakumiORM
  module Framework
    module Sinatra
      HakumiORM::Framework.register(:sinatra) { true }

      def self.registered(app)
        HakumiORM::Framework.current = :sinatra

        root = app.settings.respond_to?(:root) ? app.settings.root : nil
        logger = app.settings.respond_to?(:logger) ? app.settings.logger : nil

        HakumiORM::Framework::SinatraConfig.apply_defaults(
          HakumiORM.config,
          root: root,
          logger: logger
        )
      end
    end
  end
end
