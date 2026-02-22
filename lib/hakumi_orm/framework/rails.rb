# typed: false
# frozen_string_literal: true

require "rails/railtie"
require_relative "rails_config"

module HakumiORM
  module Framework
    class Rails < ::Rails::Railtie
      HakumiORM::Framework.register(:rails) { true }

      initializer "hakumi_orm.configure" do
        HakumiORM::Framework.current = :rails
        HakumiORM::Framework::RailsConfig.apply_defaults(
          HakumiORM.config,
          logger: ::Rails.logger
        )
      end

      initializer "hakumi_orm.autoload", before: :set_autoload_paths do |app|
        generated = ::Rails.root.join(HakumiORM.config.output_dir)
        app.config.autoload_paths << generated.to_s if generated.exist?
      end

      rake_tasks do
        require "hakumi_orm/tasks"
      end
    end
  end
end
