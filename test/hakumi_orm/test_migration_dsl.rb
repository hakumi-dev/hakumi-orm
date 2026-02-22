# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/migration"

class CreateUsersMigration < HakumiORM::Migration
  def up
    create_table("users") do |t|
      t.string "name", null: false
      t.integer "age"
    end
  end

  def down
    drop_table("users")
  end
end

class CreatePostsMigration < HakumiORM::Migration
  def up
    create_table("posts") { |t| t.string "title" }
  end

  def down
    drop_table("posts")
  end
end

class AddBioMigration < HakumiORM::Migration
  def up
    add_column "users", "bio", :text
  end

  def down
    remove_column "users", "bio"
  end
end

class RemoveAgeMigration < HakumiORM::Migration
  def up
    remove_column "users", "age"
  end

  def down; end
end

class RenameColumnMigration < HakumiORM::Migration
  def up
    rename_column "users", "name", "full_name"
  end

  def down
    rename_column "users", "full_name", "name"
  end
end

class ChangeColumnMigration < HakumiORM::Migration
  def up
    change_column "users", "age", :bigint
  end

  def down
    change_column "users", "age", :integer
  end
end

class RenameTableMigration < HakumiORM::Migration
  def up
    rename_table "old_users", "users"
  end

  def down
    rename_table "users", "old_users"
  end
end

class AddIndexMigration < HakumiORM::Migration
  def up
    add_index "users", ["email"], unique: true
  end

  def down
    remove_index "users", ["email"]
  end
end

class AddForeignKeyMigration < HakumiORM::Migration
  def up
    add_foreign_key "posts", "users", column: "user_id"
  end

  def down
    remove_foreign_key "posts", "users", column: "user_id"
  end
end

class ExecuteRawSqlMigration < HakumiORM::Migration
  def up
    execute "CREATE EXTENSION IF NOT EXISTS hstore"
  end

  def down
    execute "DROP EXTENSION IF EXISTS hstore"
  end
end

class MultiStepMigration < HakumiORM::Migration
  def up
    create_table("posts") do |t|
      t.string "title", null: false
      t.references "users", foreign_key: true
    end
    add_index "posts", ["title"]
  end

  def down
    drop_table("posts")
  end
end

class CreateCommentsMigration < HakumiORM::Migration
  def up
    create_table("comments") do |t|
      t.text "body", null: false
      t.references "posts", foreign_key: true
      t.references "users", foreign_key: true
    end
  end

  def down
    drop_table("comments")
  end
end

class ConcurrentIndexMigration < HakumiORM::Migration
  disable_ddl_transaction!

  def up
    execute "CREATE INDEX CONCURRENTLY idx_users_email ON users (email)"
  end

  def down
    execute "DROP INDEX CONCURRENTLY idx_users_email"
  end
end

class TestMigrationDsl < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
  end

  test "create_table executes SQL through adapter" do
    CreateUsersMigration.new(@adapter).up
    sqls = executed_sqls

    assert_equal 1, sqls.length
    assert_includes sqls[0], "CREATE TABLE"
    assert_includes sqls[0], '"users"'
    assert_includes sqls[0], '"name"'
  end

  test "down executes drop_table" do
    CreatePostsMigration.new(@adapter).down
    sqls = executed_sqls

    assert_equal 1, sqls.length
    assert_equal 'DROP TABLE "posts"', sqls[0]
  end

  test "add_column executes ALTER TABLE" do
    AddBioMigration.new(@adapter).up
    sqls = executed_sqls

    assert_equal 1, sqls.length
    assert_includes sqls[0], 'ALTER TABLE "users" ADD COLUMN "bio" text'
  end

  test "remove_column executes ALTER TABLE DROP" do
    RemoveAgeMigration.new(@adapter).up

    assert_includes executed_sqls[0], 'DROP COLUMN "age"'
  end

  test "rename_column executes ALTER TABLE RENAME COLUMN" do
    RenameColumnMigration.new(@adapter).up

    assert_includes executed_sqls[0], 'RENAME COLUMN "name" TO "full_name"'
  end

  test "change_column executes ALTER TABLE ALTER COLUMN" do
    ChangeColumnMigration.new(@adapter).up

    assert_includes executed_sqls[0], 'ALTER COLUMN "age" TYPE bigint'
  end

  test "rename_table executes ALTER TABLE RENAME TO" do
    RenameTableMigration.new(@adapter).up

    assert_equal 'ALTER TABLE "old_users" RENAME TO "users"', executed_sqls[0]
  end

  test "add_index executes CREATE INDEX" do
    AddIndexMigration.new(@adapter).up

    assert_includes executed_sqls[0], "CREATE UNIQUE INDEX"
  end

  test "add_foreign_key executes ALTER TABLE ADD CONSTRAINT" do
    AddForeignKeyMigration.new(@adapter).up

    assert_includes executed_sqls[0], "ADD CONSTRAINT"
    assert_includes executed_sqls[0], "FOREIGN KEY"
  end

  test "execute runs raw SQL" do
    ExecuteRawSqlMigration.new(@adapter).up

    assert_equal "CREATE EXTENSION IF NOT EXISTS hstore", executed_sqls[0]
  end

  test "multiple operations execute in order" do
    MultiStepMigration.new(@adapter).up
    sqls = executed_sqls

    assert_operator sqls.length, :>=, 2
    assert_includes sqls[0], "CREATE TABLE"
  end

  test "create_table with references produces CREATE TABLE + FK" do
    CreateCommentsMigration.new(@adapter).up
    sqls = executed_sqls

    assert_equal 3, sqls.length
    assert_includes sqls[0], "CREATE TABLE"
    assert_includes sqls[1], "FOREIGN KEY"
    assert_includes sqls[2], "FOREIGN KEY"
  end

  test "disable_ddl_transaction! sets class-level flag" do
    assert_predicate ConcurrentIndexMigration, :ddl_transaction_disabled?
    refute_predicate CreateUsersMigration, :ddl_transaction_disabled?
  end

  test "disable_ddl_transaction! migration still executes SQL" do
    ConcurrentIndexMigration.new(@adapter).up

    assert_includes executed_sqls[0], "CREATE INDEX CONCURRENTLY"
  end

  private

  def executed_sqls
    @adapter.executed_queries.map { |q| q[:sql] }
  end
end
