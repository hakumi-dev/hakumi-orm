# typed: strict
# frozen_string_literal: true

require "fileutils"

module HakumiORM
  class SetupGenerator
    extend T::Sig

    sig { params(root: String, framework: Symbol).void }
    def initialize(root:, framework: :standalone)
      @root = T.let(root, String)
      @framework = T.let(framework, Symbol)
      @created = T.let([], T::Array[String])
      @skipped = T.let([], T::Array[String])
    end

    sig { returns(T::Hash[Symbol, T::Array[String]]) }
    def run!
      create_directories
      create_initializer
      { created: @created, skipped: @skipped }
    end

    private

    sig { void }
    def create_directories
      dirs = %w[db/migrate db/associations app/db/generated]
      dirs.push("app/models", "app/contracts") if @framework == :rails

      dirs.each do |dir|
        full = File.join(@root, dir)
        if Dir.exist?(full)
          @skipped << dir
        else
          FileUtils.mkdir_p(full)
          @created << dir
        end
      end
    end

    sig { void }
    def create_initializer
      case @framework
      when :rails
        write_file("config/initializers/hakumi/orm.rb", rails_initializer)
      else
        write_file("config/hakumi/orm.rb", standalone_initializer)
      end
    end

    sig { params(rel_path: String, content: String).void }
    def write_file(rel_path, content)
      full = File.join(@root, rel_path)
      if File.exist?(full)
        @skipped << rel_path
        return
      end

      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      @created << rel_path
    end

    sig { returns(String) }
    def rails_initializer
      <<~RUBY
        # frozen_string_literal: true

        HakumiORM.configure do |c|
          c.database_url = ENV.fetch("DATABASE_URL")

          # Or configure manually:
          # c.adapter_name = :postgresql
          # c.database = "myapp_development"
          # c.host = "localhost"
          # c.username = "postgres"
          # c.password = "password"

          # Named databases:
          # c.database_config(:replica) do |r|
          #   r.database_url = ENV.fetch("REPLICA_DATABASE_URL")
          # end
        end
      RUBY
    end

    sig { returns(String) }
    def standalone_initializer
      <<~RUBY
        # frozen_string_literal: true

        require "hakumi_orm"

        HakumiORM.configure do |c|
          c.database_url = ENV.fetch("DATABASE_URL")

          # Or configure manually:
          # c.adapter_name = :postgresql
          # c.database = "myapp_development"
          # c.host = "localhost"
          # c.username = "postgres"
          # c.password = "password"

          # Named databases:
          # c.database_config(:replica) do |r|
          #   r.database_url = ENV.fetch("REPLICA_DATABASE_URL")
          # end
        end

        # Add to your Rakefile:
        # require "hakumi_orm/tasks"
      RUBY
    end
  end
end
