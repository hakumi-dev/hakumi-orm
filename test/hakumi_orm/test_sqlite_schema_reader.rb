# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/adapter/sqlite"

class TestSqliteSchemaReader < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Adapter::Sqlite.connect(":memory:")
    @adapter.exec(<<~SQL)
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        score REAL,
        active BOOLEAN DEFAULT 1
      )
    SQL
    @adapter.exec(<<~SQL)
      CREATE TABLE posts (
        id INTEGER PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id),
        title TEXT NOT NULL,
        created_at DATETIME
      )
    SQL
    @adapter.exec("CREATE UNIQUE INDEX idx_users_email ON users(email)")
    @reader = HakumiORM::Codegen::SqliteSchemaReader.new(@adapter)
  end

  def teardown
    @adapter.close
  end

  test "reads table names" do
    tables = @reader.read_tables

    assert_includes tables.keys, "users"
    assert_includes tables.keys, "posts"
    refute_includes tables.keys, "sqlite_sequence"
  end

  test "reads columns with correct types" do
    tables = @reader.read_tables
    users = tables["users"]
    col_names = users.columns.map(&:name)

    assert_includes col_names, "id"
    assert_includes col_names, "name"
    assert_includes col_names, "email"
    assert_includes col_names, "score"
    assert_includes col_names, "active"
  end

  test "detects column data types" do
    tables = @reader.read_tables
    users = tables["users"]
    types = users.columns.to_h { |c| [c.name, c.data_type] }

    assert_equal "INTEGER", types["id"]
    assert_equal "TEXT", types["name"]
    assert_equal "REAL", types["score"]
    assert_equal "BOOLEAN", types["active"]
  end

  test "detects nullable columns" do
    tables = @reader.read_tables
    users = tables["users"]
    nullable = users.columns.to_h { |c| [c.name, c.nullable] }

    refute nullable["name"]
    assert nullable["email"]
  end

  test "detects primary key" do
    tables = @reader.read_tables

    assert_equal "id", tables["users"].primary_key
    assert_equal "id", tables["posts"].primary_key
  end

  test "detects unique indexes" do
    tables = @reader.read_tables

    assert_includes tables["users"].unique_columns, "email"
  end

  test "handles table names with special characters in PRAGMA calls" do
    @adapter.exec('CREATE TABLE "my""table" (id INTEGER PRIMARY KEY, val TEXT)')
    reader = HakumiORM::Codegen::SqliteSchemaReader.new(@adapter)

    tables = reader.read_tables

    assert_includes tables.keys, 'my"table'
    tbl = tables['my"table']

    assert_equal "id", tbl.primary_key
    assert(tbl.columns.any? { |c| c.name == "val" })
  end

  test "detects foreign keys" do
    tables = @reader.read_tables
    fks = tables["posts"].foreign_keys

    assert_equal 1, fks.size

    fk = fks.first

    assert_equal "user_id", fk.column_name
    assert_equal "users", fk.foreign_table
    assert_equal "id", fk.foreign_column
  end
end
