# typed: strict
# frozen_string_literal: true

require_relative "application/fixtures_load"

module HakumiORM
  # Minitest integration inspired by ActiveRecord::TestFixtures.
  module TestFixtures
    extend T::Sig
    include Kernel
    FixtureFetch = T.type_alias do
      T.any(Fixtures::Types::FixtureRowSet, Fixtures::Types::FixtureRow, T::Array[Fixtures::Types::FixtureRow])
    end

    sig { params(base: T.class_of(Object)).void }
    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@fixture_paths, ["test/fixtures"]) unless base.instance_variable_defined?(:@fixture_paths)
      base.instance_variable_set(:@fixture_table_names, []) unless base.instance_variable_defined?(:@fixture_table_names)
      base.instance_variable_set(:@use_transactional_tests, true) unless base.instance_variable_defined?(:@use_transactional_tests)
      base.instance_variable_set(:@pre_loaded_fixtures, false) unless base.instance_variable_defined?(:@pre_loaded_fixtures)
    end

    # Class-level fixture declaration and accessor generation.
    module ClassMethods
      extend T::Sig
      include Kernel

      sig { returns(T::Array[String]) }
      def fixture_paths
        value = instance_variable_get(:@fixture_paths)
        return [] unless value

        T.cast(value, T::Array[String])
      end

      sig { params(value: T::Array[String]).void }
      def fixture_paths=(value)
        instance_variable_set(:@fixture_paths, value)
      end

      sig { returns(T::Array[String]) }
      def fixture_table_names
        value = instance_variable_get(:@fixture_table_names)
        return [] unless value

        T.cast(value, T::Array[String])
      end

      sig { params(value: T::Array[String]).void }
      def fixture_table_names=(value)
        instance_variable_set(:@fixture_table_names, value)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def use_transactional_tests
        value = instance_variable_get(:@use_transactional_tests)
        return nil if value.nil?

        T.cast(value, T::Boolean)
      end

      sig { params(value: T::Boolean).void }
      def use_transactional_tests=(value)
        instance_variable_set(:@use_transactional_tests, value)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def pre_loaded_fixtures
        value = instance_variable_get(:@pre_loaded_fixtures)
        return nil if value.nil?

        T.cast(value, T::Boolean)
      end

      sig { params(value: T::Boolean).void }
      def pre_loaded_fixtures=(value)
        instance_variable_set(:@pre_loaded_fixtures, value)
      end

      sig { params(fixture_set_names: T.any(String, Symbol)).void }
      def fixtures(*fixture_set_names)
        names =
          if fixture_set_names.first == :all
            Kernel.raise StandardError, "No fixture path found. Please set #{self}.fixture_paths." if fixture_paths.empty?

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

      sig { params(fixture_set_names: T.nilable(T::Array[String])).void }
      def setup_fixture_accessors(fixture_set_names = nil)
        _ = fixture_set_names
        # No dynamic accessor methods; call fixture(:table, :label) explicitly.
      end
    end

    sig { void }
    def before_setup
      setup_fixtures
      super
    end

    sig { void }
    def after_teardown
      super
    ensure
      teardown_fixtures
    end

    sig do
      params(
        fixture_set_name: T.any(String, Symbol),
        fixture_names: T.nilable(T.any(String, Symbol, T::Array[T.any(String, Symbol)]))
      ).returns(FixtureFetch)
    end
    def fixture(fixture_set_name, fixture_names = nil)
      table = fixture_set_name.to_s.tr("/", "_")
      loaded = @loaded_fixtures
      rows = (loaded || {})[table]
      Kernel.raise StandardError, "No fixture set named '#{fixture_set_name}'" unless rows

      names = T.let(
        case fixture_names
        when nil then []
        when Array then fixture_names.map(&:to_s)
        else [fixture_names.to_s]
        end,
        T::Array[String]
      )

      return rows if names.empty?
      return rows.fetch(names.fetch(0)) if names.length == 1

      names.map { |name| rows.fetch(name) }
    end

    private

    sig { void }
    def setup_fixtures
      @fixture_tx_open = T.let(false, T.nilable(T::Boolean))
      pre_loaded = T.cast(self.class.instance_variable_get(:@pre_loaded_fixtures), T.nilable(T::Boolean)) == true
      transactional = T.cast(self.class.instance_variable_get(:@use_transactional_tests), T.nilable(T::Boolean)) == true
      Kernel.raise "pre_loaded_fixtures requires use_transactional_tests" if pre_loaded && !transactional

      @loaded_fixtures = T.let(
        if pre_loaded
          cache = self.class.instance_variable_get(:@_hakumi_loaded_fixtures)
          cache ? T.cast(cache, Fixtures::Types::LoadedFixtures) : load_fixtures_once!
        else
          load_fixtures_data!
        end,
        T.nilable(Fixtures::Types::LoadedFixtures)
      )

      return unless transactional

      @fixture_tx_open = T.let(true, T.nilable(T::Boolean))
      HakumiORM.adapter.exec("BEGIN").close
    end

    sig { void }
    def teardown_fixtures
      return unless @fixture_tx_open

      begin
        HakumiORM.adapter.exec("ROLLBACK").close
      rescue StandardError
        nil
      ensure
        @fixture_tx_open = T.let(false, T.nilable(T::Boolean))
      end
    end

    sig { returns(Fixtures::Types::LoadedFixtures) }
    def load_fixtures_once!
      data = load_fixtures_data!
      self.class.instance_variable_set(:@_hakumi_loaded_fixtures, data)
      data
    end

    sig { returns(Fixtures::Types::LoadedFixtures) }
    def load_fixtures_data!
      names = self.class.fixture_table_names
      return {} if names.empty?

      config = HakumiORM.config
      adapter = config.adapter
      Kernel.raise HakumiORM::Error, "No database configured. Set HakumiORM.config.database first." unless adapter

      self.class.fixture_paths.each_with_object({}) do |path, merged|
        data = HakumiORM::Application::FixturesLoad.load_with_data!(
          config: config,
          adapter: adapter,
          request: {
            base_path: path,
            fixtures_dir: nil,
            only_names: names,
            verify_foreign_keys: false
          }
        )
        data.each { |table_name, rows| merged[table_name] = rows }
      end
    end
  end
end
