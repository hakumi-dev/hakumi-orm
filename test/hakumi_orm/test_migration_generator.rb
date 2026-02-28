# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "hakumi_orm/migration"

class TestMigrationGenerator < HakumiORM::TestCase
  def setup
    @dir = Dir.mktmpdir("hakumi_migrations")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  test "generates migration file with timestamp and snake_case name" do
    HakumiORM::Migration::FileGenerator.generate(name: "create_users", path: @dir)

    files = Dir.children(@dir).select { |f| f.end_with?(".rb") }

    assert_equal 1, files.length
    assert_match(/\A\d{14}_create_users\.rb\z/, files[0])
  end

  test "generated file contains valid migration class" do
    HakumiORM::Migration::FileGenerator.generate(name: "create_users", path: @dir)

    file = Dir.children(@dir).find { |f| f.end_with?(".rb") }
    content = File.read(File.join(@dir, file))

    assert_includes content, "class CreateUsers < HakumiORM::Migration"
    assert_includes content, "def up"
    assert_includes content, "def down"
    assert_includes content, "# typed: false"
    assert_includes content, "# frozen_string_literal: true"
  end

  test "handles multi-word names correctly" do
    HakumiORM::Migration::FileGenerator.generate(name: "add_email_to_users", path: @dir)

    file = Dir.children(@dir).find { |f| f.end_with?(".rb") }
    content = File.read(File.join(@dir, file))

    assert_includes content, "class AddEmailToUsers < HakumiORM::Migration"
  end

  test "creates output directory if it does not exist" do
    nested = File.join(@dir, "db", "migrate")
    HakumiORM::Migration::FileGenerator.generate(name: "create_posts", path: nested)

    assert Dir.exist?(nested)
    assert_equal 1, Dir.children(nested).length
  end

  test "does not overwrite existing migration with same name" do
    HakumiORM::Migration::FileGenerator.generate(name: "create_users", path: @dir)
    sleep(0.01)

    assert_raises(HakumiORM::Error) do
      HakumiORM::Migration::FileGenerator.generate(name: "create_users", path: @dir)
    end
  end

  test "bumps timestamp when collision with existing file in same second" do
    now = Time.new(2026, 1, 1, 12, 0, 0)
    HakumiORM::Migration::FileGenerator.generate(name: "create_users", path: @dir, now: now)
    HakumiORM::Migration::FileGenerator.generate(name: "create_posts", path: @dir, now: now)

    files = Dir.children(@dir).sort
    timestamps = files.map { |f| f[0, 14] }

    assert_equal 2, files.length
    assert_equal %w[20260101120000 20260101120001], timestamps
  end

  test "bumps timestamp multiple times if needed" do
    now = Time.new(2026, 1, 1, 12, 0, 0)
    HakumiORM::Migration::FileGenerator.generate(name: "step_one", path: @dir, now: now)
    HakumiORM::Migration::FileGenerator.generate(name: "step_two", path: @dir, now: now)
    HakumiORM::Migration::FileGenerator.generate(name: "step_three", path: @dir, now: now)

    files = Dir.children(@dir).sort
    timestamps = files.map { |f| f[0, 14] }

    assert_equal %w[20260101120000 20260101120001 20260101120002], timestamps.sort
  end

  test "rejects name with hyphens" do
    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Migration::FileGenerator.generate(name: "create-users", path: @dir)
    end

    assert_includes err.message, "must contain only"
  end

  test "rejects name with spaces" do
    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Migration::FileGenerator.generate(name: "create users", path: @dir)
    end

    assert_includes err.message, "must contain only"
  end

  test "rejects empty name" do
    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Migration::FileGenerator.generate(name: "", path: @dir)
    end

    assert_includes err.message, "must contain only"
  end

  test "rejects name starting with a digit" do
    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Migration::FileGenerator.generate(name: "123_create", path: @dir)
    end

    assert_includes err.message, "must start with a letter"
  end

  test "accepts valid snake_case name" do
    filepath = HakumiORM::Migration::FileGenerator.generate(name: "add_email_index_to_users", path: @dir)

    assert_path_exists filepath
  end
end
