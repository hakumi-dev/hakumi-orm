# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "hakumi_orm/adapter/sqlite_result"
require "hakumi_orm/adapter/sqlite"
require "hakumi_orm/test_fixtures"

class TestTestFixtures < HakumiORM::TestCase
  def setup
    @original_adapter = HakumiORM.config.adapter
    @original_adapter_name = HakumiORM.config.adapter_name
    @original_database = HakumiORM.config.database
  end

  def teardown
    HakumiORM.config.adapter = @original_adapter
    HakumiORM.config.adapter_name = @original_adapter_name
    HakumiORM.config.database = @original_database
  end

  test "fixture accessors and fixture helper return labeled rows" do
    Dir.mktmpdir do |dir|
      adapter, fixtures_dir = setup_sqlite_with_fixtures!(dir)

      test_case = Class.new(Minitest::Test) do
        include HakumiORM::TestFixtures

        self.fixture_paths = [fixtures_dir]
        fixtures :users
        define_method(:noop) { nil }
      end

      instance = test_case.new(:noop)
      instance.before_setup

      assert_equal "Alice", instance.users(:alice)["name"]
      assert_equal "Bob", instance.fixture(:users, :bob)["name"]
    ensure
      instance&.after_teardown
      adapter&.close
    end
  end

  test "transactional fixtures rollback per test" do
    Dir.mktmpdir do |dir|
      adapter, fixtures_dir = setup_sqlite_with_fixtures!(dir)

      test_case = Class.new(Minitest::Test) do
        include HakumiORM::TestFixtures

        self.fixture_paths = [fixtures_dir]
        fixtures :users
        define_method(:noop) { nil }
      end

      instance = test_case.new(:noop)
      instance.before_setup
      adapter.exec('INSERT INTO "users" (id, name) VALUES (3, "Eve")').close

      assert_equal 3, adapter.exec('SELECT COUNT(*) FROM "users"').get_value(0, 0)
      instance.after_teardown

      assert_equal 2, adapter.exec('SELECT COUNT(*) FROM "users"').get_value(0, 0)
    ensure
      adapter&.close
    end
  end

  test "pre_loaded_fixtures requires transactional tests" do
    Dir.mktmpdir do |dir|
      adapter, fixtures_dir = setup_sqlite_with_fixtures!(dir)

      test_case = Class.new(Minitest::Test) do
        include HakumiORM::TestFixtures

        self.fixture_paths = [fixtures_dir]
        self.use_transactional_tests = false
        self.pre_loaded_fixtures = true
        fixtures :users
        define_method(:noop) { nil }
      end

      instance = test_case.new(:noop)
      error = assert_raises(RuntimeError) { instance.before_setup }
      assert_includes error.message, "pre_loaded_fixtures requires use_transactional_tests"
    ensure
      adapter&.close
    end
  end

  private

  def setup_sqlite_with_fixtures!(dir)
    db_path = File.join(dir, "fixtures.sqlite3")
    fixtures_dir = File.join(dir, "test", "fixtures")
    FileUtils.mkdir_p(fixtures_dir)
    File.write(File.join(fixtures_dir, "users.yml"), <<~YAML)
      alice:
        id: 1
        name: Alice
      bob:
        id: 2
        name: Bob
    YAML

    adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
    adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close

    HakumiORM.config.adapter = adapter
    HakumiORM.config.adapter_name = :sqlite
    HakumiORM.config.database = db_path

    [adapter, fixtures_dir]
  end
end
