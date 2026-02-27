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
    @original_verify_foreign_keys_for_fixtures = HakumiORM.config.verify_foreign_keys_for_fixtures
    @original_env_fixtures = ENV.fetch("FIXTURES", nil)
    @original_env_fixtures_dir = ENV.fetch("FIXTURES_DIR", nil)
    @original_env_fixtures_path = ENV.fetch("FIXTURES_PATH", nil)
    @original_env_verify_fixture_fks = ENV.fetch("HAKUMI_VERIFY_FIXTURE_FKS", nil)
  end

  def teardown
    HakumiORM.config.seeds_path = @original_seeds_path
    HakumiORM.config.fixtures_path = @original_fixtures_path
    HakumiORM.config.adapter = @original_adapter
    HakumiORM.config.adapter_name = @original_adapter_name
    HakumiORM.config.database = @original_database
    HakumiORM.config.verify_foreign_keys_for_fixtures = @original_verify_foreign_keys_for_fixtures
    ENV["FIXTURES"] = @original_env_fixtures
    ENV["FIXTURES_DIR"] = @original_env_fixtures_dir
    ENV["FIXTURES_PATH"] = @original_env_fixtures_path
    ENV["HAKUMI_VERIFY_FIXTURE_FKS"] = @original_env_verify_fixture_fks
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

  test "run_prepare delegates to run_migrate" do
    calls = []
    original = HakumiORM::TaskCommands.method(:run_migrate)
    HakumiORM::TaskCommands.define_singleton_method(:run_migrate) do |task_prefix:|
      calls << task_prefix
    end

    HakumiORM::TaskCommands.run_prepare(task_prefix: "db:")

    assert_equal ["db:"], calls
  ensure
    HakumiORM::TaskCommands.define_singleton_method(:run_migrate, original)
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

  test "run_fixtures_load auto-generates deterministic integer id when missing" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures_ids.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(File.join(fixtures_dir, "users.yml"), "alice:\n  name: Alice\nbob:\n  name: Bob\n")

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir

      HakumiORM::TaskCommands.run_fixtures_load

      result = adapter.exec('SELECT id, name FROM "users" ORDER BY name ASC')
      rows = result.values
      result.close

      assert_equal 2, rows.size
      assert_equal "Alice", rows[0][1]
      assert_equal "Bob", rows[1][1]
      refute_equal rows[0][0], rows[1][0]
      assert_predicate rows[0][0], :positive?
      assert_predicate rows[1][0], :positive?
    ensure
      adapter.close
    end
  end

  test "run_fixtures_load resolves fk label references and association keys" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures_refs.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("PRAGMA foreign_keys = ON").close
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close
      adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id))").close

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(File.join(fixtures_dir, "posts.yml"), "welcome:\n  user: alice\n  title: Hello\n")
      File.write(File.join(fixtures_dir, "users.yml"), "alice:\n  name: Alice\n")

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir

      HakumiORM::TaskCommands.run_fixtures_load

      user_id = adapter.exec('SELECT id FROM "users" WHERE name = "Alice"').get_value(0, 0)
      post_user_id = adapter.exec('SELECT user_id FROM "posts" WHERE title = "Hello"').get_value(0, 0)

      assert_equal user_id, post_user_id
    ensure
      adapter.close
    end
  end

  test "run_fixtures_load raises on orphan fk when verification enabled" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures_fk_verify.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("PRAGMA foreign_keys = OFF").close
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close
      adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, title TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id))").close

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(File.join(fixtures_dir, "posts.yml"), "broken:\n  user_id: ghost\n  title: Broken\n")
      File.write(File.join(fixtures_dir, "users.yml"), "alice:\n  name: Alice\n")

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir
      HakumiORM.config.verify_foreign_keys_for_fixtures = true

      error = assert_raises(HakumiORM::Error) { HakumiORM::TaskCommands.run_fixtures_load }
      assert_includes error.message, "Fixture foreign key check failed"
      assert_includes error.message, "posts.user_id"
    ensure
      adapter.close
    end
  end

  test "run_fixtures_load expands multi-label fk references for join rows" do
    require "hakumi_orm/adapter/sqlite_result"
    require "hakumi_orm/adapter/sqlite"

    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "fixtures_join_expand.sqlite3")
      adapter = HakumiORM::Adapter::Sqlite.connect(db_path)
      adapter.exec("PRAGMA foreign_keys = ON").close
      adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close
      adapter.exec("CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT NOT NULL)").close
      adapter.exec(<<~SQL).close
        CREATE TABLE memberships (
          id INTEGER PRIMARY KEY,
          user_id INTEGER NOT NULL,
          team_id INTEGER NOT NULL,
          FOREIGN KEY(user_id) REFERENCES users(id),
          FOREIGN KEY(team_id) REFERENCES teams(id)
        )
      SQL

      fixtures_dir = File.join(dir, "test", "fixtures")
      FileUtils.mkdir_p(fixtures_dir)
      File.write(File.join(fixtures_dir, "users.yml"), "alice:\n  name: Alice\nbob:\n  name: Bob\n")
      File.write(File.join(fixtures_dir, "teams.yml"), "core:\n  name: Core\n")
      File.write(
        File.join(fixtures_dir, "memberships.yml"),
        <<~YAML
          duo_csv:
            user: alice,bob
            team: core
          duo_array:
            user:
              - alice
              - bob
            team: core
        YAML
      )

      HakumiORM.config.adapter = adapter
      HakumiORM.config.adapter_name = :sqlite
      HakumiORM.config.database = db_path
      HakumiORM.config.fixtures_path = fixtures_dir

      HakumiORM::TaskCommands.run_fixtures_load

      count = adapter.exec('SELECT COUNT(*) FROM "memberships"').get_value(0, 0)
      user_names = adapter.exec(<<~SQL).values.map { |row| row[0] }
        SELECT u.name
        FROM memberships m
        JOIN users u ON u.id = m.user_id
        ORDER BY m.id ASC
      SQL

      assert_equal 4, count
      assert_equal %w[Alice Alice Bob Bob], user_names.sort
    ensure
      adapter.close
    end
  end
end
