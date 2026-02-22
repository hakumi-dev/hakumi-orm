# typed: false
# frozen_string_literal: true

require "rails/railtie"
require_relative "rails_config"

module HakumiORM
  module Framework
    class Rails < ::Rails::Railtie
      HakumiORM::Framework.register(:rails) { true }

      config.before_configuration do
        %w[app/models app/contracts].each do |dir|
          full = ::Rails.root.join(dir).to_s
          ::Rails.autoloaders.each { |loader| loader.ignore(full) } if ::Rails.respond_to?(:autoloaders)
        end
      end

      initializer "hakumi_orm.configure" do
        HakumiORM::Framework.current = :rails
        HakumiORM::Framework::RailsConfig.apply_defaults(
          HakumiORM.config,
          log_level: ::Rails.configuration.log_level || :info
        )
      end

      initializer "hakumi_orm.load_generated" do
        manifest = ::Rails.root.join(HakumiORM.config.output_dir, "manifest.rb")
        require manifest.to_s if manifest.exist?

        %w[contracts_dir models_dir].each do |dir_method|
          dir = HakumiORM.config.send(dir_method)
          next unless dir

          path = ::Rails.root.join(dir)
          next unless path.exist?

          Dir[path.join("**", "*.rb")].each { |f| require f }
        end
      end

      rake_tasks do
        require "hakumi_orm/tasks"

        %w[migrate rollback migrate:status version generate associations].each do |t|
          Rake::Task["hakumi:#{t}"].enhance([:environment])
        end
      end
    end
  end
end
