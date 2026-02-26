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
        apply_rails_logger_defaults!(HakumiORM.config)
      end

      initializer "hakumi_orm.load_generated" do
        config.after_initialize do
          load_generated_hakumi_code!
        end
      end

      rake_tasks do
        require "hakumi_orm/tasks"
      end

      private

      def apply_rails_logger_defaults!(config)
        if defined?(::ActiveSupport::BroadcastLogger) &&
           !(::ActiveSupport::BroadcastLogger <= HakumiORM::Loggable)
          ::ActiveSupport::BroadcastLogger.include(HakumiORM::Loggable)
        end

        config.logger = ::Rails.logger if defined?(::Rails.logger) && ::Rails.logger
        return unless ::Rails.env.development?

        config.pretty_sql_logs = true
        config.colorize_sql_logs = $stdout.tty?
      end

      def load_generated_hakumi_code!
        return if running_hakumi_rake_task?

        manifest = path_from_root_or_absolute(HakumiORM.config.output_dir).join("manifest.rb")
        return unless manifest.exist?

        require manifest.to_s

        %w[models_dir contracts_dir].each do |dir_method|
          dir = HakumiORM.config.public_send(dir_method)
          next unless dir

          path = path_from_root_or_absolute(dir)
          next unless path.exist?

          Dir[path.join("**", "*.rb")].sort_by { |f| f.count(File::SEPARATOR) }.each { |f| require f }
        end
      end

      def path_from_root_or_absolute(path)
        pn = Pathname.new(path)
        pn.absolute? ? pn : ::Rails.root.join(path)
      end

      def running_hakumi_rake_task?
        return false unless defined?(::Rake) && ::Rake.respond_to?(:application)

        app = ::Rake.application
        return false unless app

        app.top_level_tasks.any? { |t| t.start_with?("db:", "hakumi:") }
      rescue StandardError
        false
      end
    end
  end
end
