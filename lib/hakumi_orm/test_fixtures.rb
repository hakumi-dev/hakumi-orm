# typed: false
# frozen_string_literal: true

require_relative "fixtures/loader"

module HakumiORM
  # Minitest integration inspired by ActiveRecord::TestFixtures.
  module TestFixtures
    def self.included(base)
      base.extend(ClassMethods)
      base.class_eval do
        class << self
          attr_accessor :fixture_paths, :fixture_table_names, :use_transactional_tests, :pre_loaded_fixtures
        end

        self.fixture_paths ||= ["test/fixtures"]
        self.fixture_table_names ||= []
        self.use_transactional_tests = true if use_transactional_tests.nil?
        self.pre_loaded_fixtures = false if pre_loaded_fixtures.nil?
      end
    end

    # Class-level fixture declaration and accessor generation.
    module ClassMethods
      def fixtures(*fixture_set_names)
        names =
          if fixture_set_names.first == :all
            raise StandardError, "No fixture path found. Please set #{self}.fixture_paths." if fixture_paths.nil? || fixture_paths.empty?

            fixture_paths.flat_map do |path|
              root = File.expand_path(path, Dir.pwd)
              Dir.glob(File.join(root, "**", "*.yml"))
                 .reject { |f| f.start_with?(File.join(root, "files")) }
                 .map { |f| f.delete_prefix("#{root}/").delete_suffix(".yml") }
            end.uniq
          else
            fixture_set_names.flatten.map(&:to_s)
          end

        self.fixture_table_names = names.sort
        setup_fixture_accessors(names)
      end

      def setup_fixture_accessors(fixture_set_names = fixture_table_names)
        fixture_set_names.each do |name|
          method_name = name.tr("/", "_")
          define_method(method_name) do |*fixture_names|
            fixture(name, *fixture_names)
          end
        end
      end
    end

    def before_setup
      setup_fixtures
      super
    end

    def after_teardown
      super
    ensure
      teardown_fixtures
    end

    def fixture(fixture_set_name, *fixture_names)
      table = fixture_set_name.to_s.tr("/", "_")
      rows = (@loaded_fixtures || {})[table]
      raise StandardError, "No fixture set named '#{fixture_set_name}'" unless rows

      return rows if fixture_names.empty?
      return rows.fetch(fixture_names.first.to_s) if fixture_names.length == 1

      fixture_names.map { |name| rows.fetch(name.to_s) }
    end

    private

    def setup_fixtures
      raise "pre_loaded_fixtures requires use_transactional_tests" if self.class.pre_loaded_fixtures && !self.class.use_transactional_tests

      @loaded_fixtures =
        if self.class.pre_loaded_fixtures
          self.class.instance_variable_get(:@_hakumi_loaded_fixtures) || load_fixtures_once!
        else
          load_fixtures_data!
        end

      return unless self.class.use_transactional_tests

      @fixture_tx_open = true
      HakumiORM.adapter.exec("BEGIN").close
    end

    def teardown_fixtures
      return unless @fixture_tx_open

      begin
        HakumiORM.adapter.exec("ROLLBACK").close
      rescue StandardError
        nil
      ensure
        @fixture_tx_open = false
      end
    end

    def load_fixtures_once!
      data = load_fixtures_data!
      self.class.instance_variable_set(:@_hakumi_loaded_fixtures, data)
      data
    end

    def load_fixtures_data!
      names = self.class.fixture_table_names
      return {} if names.empty?

      config = HakumiORM.config
      adapter = config.adapter
      raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

      tables = HakumiORM::Application::SchemaIntrospection.read_tables(config, adapter)
      loader = HakumiORM::Fixtures::Loader.new(adapter: adapter, tables: tables)

      self.class.fixture_paths.each_with_object({}) do |path, merged|
        data = loader.load_with_data!(base_path: path, only_names: names)
        data.each { |table_name, rows| merged[table_name] = rows }
      end
    end
  end
end
