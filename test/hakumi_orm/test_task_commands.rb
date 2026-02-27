# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/task_commands"
require "tmpdir"
require "stringio"
require "fileutils"

class TestTaskCommands < HakumiORM::TestCase
  def setup
    @original_seeds_path = HakumiORM.config.seeds_path
    @original_fixtures_path = HakumiORM.config.fixtures_path
    @original_adapter = HakumiORM.config.adapter
    @original_adapter_name = HakumiORM.config.adapter_name
    @original_database = HakumiORM.config.database
    @original_env_fixtures = ENV.fetch("FIXTURES", nil)
    @original_env_fixtures_dir = ENV.fetch("FIXTURES_DIR", nil)
    @original_env_fixtures_path = ENV.fetch("FIXTURES_PATH", nil)
  end

  def teardown
    HakumiORM.config.seeds_path = @original_seeds_path
    HakumiORM.config.fixtures_path = @original_fixtures_path
    HakumiORM.config.adapter = @original_adapter
    HakumiORM.config.adapter_name = @original_adapter_name
    HakumiORM.config.database = @original_database
    ENV["FIXTURES"] = @original_env_fixtures
    ENV["FIXTURES_DIR"] = @original_env_fixtures_dir
    ENV["FIXTURES_PATH"] = @original_env_fixtures_path
  end

  test "run_seed warns when seed file is missing" do
    Dir.mktmpdir do |dir|
      HakumiORM.config.seeds_path = File.join(dir, "missing_seeds.rb")
      out, err = capture_io { HakumiORM::TaskCommands.run_seed }

      assert_empty out
      assert_includes err, "Seed file not found"
    end
  end

  test "run_seed loads seed file and prints completion message" do
    Dir.mktmpdir do |dir|
      seed_path = File.join(dir, "seeds.rb")
      marker_path = File.join(dir, "seed_marker.txt")
      File.write(seed_path, "File.write(#{marker_path.inspect}, \"ok\")\n")
      HakumiORM.config.seeds_path = seed_path

      out, = capture_io { HakumiORM::TaskCommands.run_seed }

      assert_equal "ok", File.read(marker_path)
      assert_includes out, "Seed completed from"
      assert_includes out, seed_path
    end
  end

  test "run_fixtures_load loads yaml fixtures into sqlite database" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, active BOOLEAN NOT NULL)").close

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(
        File.join(fixtures_dir, "users.yml"),
        <<~YAML
          alice:
            id: 1
            name: Alice
            active: true
          bob:
            id: 2
            name: Bob
            active: false
        YAML
      )

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir

      out, = capture_io { HakumiORM::TaskCommands.run_fixtures_load }

      result = adapter.exec('SELECT id, name, active FROM "users" ORDER BY id ASC')
      rows = result.values
      result.close

      assert_equal [[1, "Alice", 1], [2, "Bob", 0]], rows
      assert_includes out, "Loaded fixtures"
      assert_includes out, fixtures_dir
    ensure
      adapter.close
    end
  end

  test "run_fixtures_load respects FIXTURES filter" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures_filter.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close
      adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT NOT NULL)").close

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(File.join(fixtures_dir, "users.yml"), "alice:\n  id: 1\n  name: Alice\n")
      File.write(File.join(fixtures_dir, "posts.yml"), "welcome:\n  id: 1\n  title: Hello\n")

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir
      ENV["FIXTURES"] = "users"

      HakumiORM::TaskCommands.run_fixtures_load

      users_count = adapter.exec('SELECT COUNT(*) FROM "users"').get_value(0, 0)
      posts_count = adapter.exec('SELECT COUNT(*) FROM "posts"').get_value(0, 0)

      assert_equal 1, users_count
      assert_equal 0, posts_count
    ensure
      adapter.close
    end
  end
end
