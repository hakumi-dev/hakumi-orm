# typed: false
# frozen_string_literal: true

require_relative "sinatra_config"

module HakumiORM
  module Framework
    # Hooks Sinatra app boot to apply Hakumi ORM defaults.
    module Sinatra
      HakumiORM::Framework.register(:sinatra) { true }

      def self.registered(app)
        HakumiORM::Framework.current = :sinatra

        root = app.settings.respond_to?(:root) ? app.settings.root : nil

        HakumiORM::Framework::SinatraConfig.apply_defaults(
          HakumiORM.config,
          root: root
        )
      end
    end
  end
end
