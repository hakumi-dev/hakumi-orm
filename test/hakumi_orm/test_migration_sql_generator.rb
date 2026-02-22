# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/migration"

class TestMigrationSqlGenerator < HakumiORM::TestCase
  def setup
    @pg = HakumiORM::Dialect::Postgresql.new
    @mysql = HakumiORM::Dialect::Mysql.new
    @sqlite = HakumiORM::Dialect::Sqlite.new
    @gen = HakumiORM::Migration::SqlGenerator
  end

  test "create_table with PG produces bigserial PK and quoted identifiers" do
    td = HakumiORM::Migration::TableDefinition.new("users")
    td.string "name", null: false
    td.integer "age"

    sql = @gen.create_table(td, @pg)

    assert_includes sql, 'CREATE TABLE "users"'
    assert_includes sql, '"id" bigserial PRIMARY KEY'
    assert_includes sql, '"name" varchar(255) NOT NULL'
    assert_includes sql, '"age" integer'
    refute_includes sql, '"age" integer NOT NULL'
  end

  test "create_table with MySQL uses backtick quoting and AUTO_INCREMENT" do
    td = HakumiORM::Migration::TableDefinition.new("users")
    td.string "name", null: false

    sql = @gen.create_table(td, @mysql)

    assert_includes sql, "CREATE TABLE `users`"
    assert_includes sql, "`id` bigint AUTO_INCREMENT PRIMARY KEY"
    assert_includes sql, "`name` varchar(255) NOT NULL"
  end

  test "create_table with SQLite uses INTEGER PRIMARY KEY AUTOINCREMENT" do
    td = HakumiORM::Migration::TableDefinition.new("users")
    td.string "name", null: false

    sql = @gen.create_table(td, @sqlite)

    assert_includes sql, 'CREATE TABLE "users"'
    assert_includes sql, '"id" INTEGER PRIMARY KEY AUTOINCREMENT'
    assert_includes sql, '"name" TEXT NOT NULL'
  end

  test "create_table with id: false omits PK column" do
    td = HakumiORM::Migration::TableDefinition.new("join_table", id: false)
    td.integer "user_id", null: false
    td.integer "role_id", null: false

    sql = @gen.create_table(td, @pg)

    refute_includes sql, "PRIMARY KEY"
    assert_includes sql, '"user_id" integer NOT NULL'
    assert_includes sql, '"role_id" integer NOT NULL'
  end

  test "create_table with id: :uuid uses UUID PK" do
    td = HakumiORM::Migration::TableDefinition.new("tokens", id: :uuid)
    td.string "value", null: false

    sql = @gen.create_table(td, @pg)

    assert_includes sql, '"id" uuid PRIMARY KEY'
  end

  test "create_table with default value" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.boolean "published", null: false, default: "false"

    sql = @gen.create_table(td, @pg)

    assert_includes sql, '"published" boolean NOT NULL DEFAULT false'
  end

  test "create_table with decimal precision and scale" do
    td = HakumiORM::Migration::TableDefinition.new("products")
    td.decimal "price", null: false, precision: 10, scale: 2

    sql = @gen.create_table(td, @pg)

    assert_includes sql, '"price" decimal(10,2) NOT NULL'
  end

  test "create_table with string limit" do
    td = HakumiORM::Migration::TableDefinition.new("users")
    td.string "code", null: false, limit: 6

    sql = @gen.create_table(td, @pg)

    assert_includes sql, '"code" varchar(6) NOT NULL'
  end

  test "create_table with references produces FK constraint" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.string "title", null: false
    td.references "users", foreign_key: true

    sqls = @gen.create_table_with_fks(td, @pg)

    assert_equal 2, sqls.length
    assert_includes sqls[0], '"user_id" bigint NOT NULL'
    assert_includes sqls[1], 'ALTER TABLE "posts" ADD CONSTRAINT'
    assert_includes sqls[1], 'FOREIGN KEY ("user_id") REFERENCES "users" ("id")'
  end

  test "type mapping for PG covers all types" do
    mappings = {
      string: "varchar(255)", text: "text", integer: "integer", bigint: "bigint",
      float: "double precision", boolean: "boolean", date: "date",
      datetime: "timestamp", timestamp: "timestamp", binary: "bytea",
      json: "json", jsonb: "jsonb", uuid: "uuid", inet: "inet", cidr: "cidr",
      hstore: "hstore", integer_array: "integer[]", string_array: "text[]",
      float_array: "double precision[]", boolean_array: "boolean[]"
    }

    mappings.each do |type, expected_sql|
      result = @gen.column_type_sql(type, @pg)

      assert_equal expected_sql, result, "PG type mapping for :#{type}"
    end
  end

  test "type mapping for MySQL differs where expected" do
    assert_equal "tinyint(1)", @gen.column_type_sql(:boolean, @mysql)
    assert_equal "double", @gen.column_type_sql(:float, @mysql)
    assert_equal "blob", @gen.column_type_sql(:binary, @mysql)
    assert_equal "char(36)", @gen.column_type_sql(:uuid, @mysql)
  end

  test "type mapping for SQLite collapses to storage classes" do
    assert_equal "TEXT", @gen.column_type_sql(:string, @sqlite)
    assert_equal "INTEGER", @gen.column_type_sql(:integer, @sqlite)
    assert_equal "INTEGER", @gen.column_type_sql(:boolean, @sqlite)
    assert_equal "REAL", @gen.column_type_sql(:float, @sqlite)
    assert_equal "TEXT", @gen.column_type_sql(:uuid, @sqlite)
  end

  test "array types raise on MySQL" do
    assert_raises(HakumiORM::Error) { @gen.column_type_sql(:integer_array, @mysql) }
  end

  test "array types raise on SQLite" do
    assert_raises(HakumiORM::Error) { @gen.column_type_sql(:integer_array, @sqlite) }
  end

  test "drop_table produces correct SQL" do
    sql = @gen.drop_table("users", @pg)

    assert_equal 'DROP TABLE "users"', sql
  end

  test "rename_table produces correct SQL" do
    sql = @gen.rename_table("old_users", "users", @pg)

    assert_equal 'ALTER TABLE "old_users" RENAME TO "users"', sql
  end

  test "add_column produces correct SQL" do
    col = HakumiORM::Migration::ColumnDefinition.new(name: "age", type: :integer, null: true)

    sql = @gen.add_column("users", col, @pg)

    assert_equal 'ALTER TABLE "users" ADD COLUMN "age" integer', sql
  end

  test "add_column with NOT NULL and default" do
    col = HakumiORM::Migration::ColumnDefinition.new(name: "active", type: :boolean, null: false, default: "true")

    sql = @gen.add_column("users", col, @pg)

    assert_equal 'ALTER TABLE "users" ADD COLUMN "active" boolean NOT NULL DEFAULT true', sql
  end

  test "remove_column produces correct SQL" do
    sql = @gen.remove_column("users", "age", @pg)

    assert_equal 'ALTER TABLE "users" DROP COLUMN "age"', sql
  end

  test "change_column produces correct SQL for PG" do
    col = HakumiORM::Migration::ColumnDefinition.new(name: "age", type: :bigint)

    sql = @gen.change_column("users", col, @pg)

    assert_includes sql, 'ALTER TABLE "users" ALTER COLUMN "age" TYPE bigint'
  end

  test "rename_column produces correct SQL" do
    sql = @gen.rename_column("users", "name", "full_name", @pg)

    assert_equal 'ALTER TABLE "users" RENAME COLUMN "name" TO "full_name"', sql
  end

  test "add_index produces correct SQL" do
    sql = @gen.add_index("users", ["email"], dialect: @pg, unique: true)

    assert_includes sql, "CREATE UNIQUE INDEX"
    assert_includes sql, 'ON "users"'
  end

  test "add_index non-unique" do
    sql = @gen.add_index("users", %w[last_name first_name], dialect: @pg, unique: false)

    assert_includes sql, "CREATE INDEX"
    refute_includes sql, "UNIQUE"
  end

  test "remove_index by columns" do
    sql = @gen.remove_index("users", ["email"], dialect: @pg)

    assert_includes sql, "DROP INDEX"
  end

  test "add_foreign_key produces correct SQL" do
    sql = @gen.add_foreign_key("posts", "users", column: "user_id", dialect: @pg)

    assert_includes sql, 'ALTER TABLE "posts" ADD CONSTRAINT "fk_posts_user_id"'
    assert_includes sql, 'FOREIGN KEY ("user_id") REFERENCES "users" ("id")'
  end

  test "remove_foreign_key produces correct SQL" do
    sql = @gen.remove_foreign_key("posts", "users", dialect: @pg, column: "user_id")

    assert_includes sql, 'ALTER TABLE "posts" DROP CONSTRAINT "fk_posts_user_id"'
  end

  test "add_foreign_key with on_delete cascade" do
    sql = @gen.add_foreign_key("posts", "users", column: "user_id", dialect: @pg, on_delete: :cascade)

    assert_includes sql, "ON DELETE CASCADE"
  end

  test "add_foreign_key with on_delete set_null" do
    sql = @gen.add_foreign_key("posts", "users", column: "user_id", dialect: @pg, on_delete: :set_null)

    assert_includes sql, "ON DELETE SET NULL"
  end

  test "add_foreign_key with on_delete restrict" do
    sql = @gen.add_foreign_key("posts", "users", column: "user_id", dialect: @pg, on_delete: :restrict)

    assert_includes sql, "ON DELETE RESTRICT"
  end

  test "create_table with id: :serial uses serial PK" do
    td = HakumiORM::Migration::TableDefinition.new("counters", id: :serial)
    td.string "name", null: false

    pg_sql = @gen.create_table(td, @pg)
    mysql_sql = @gen.create_table(td, @mysql)
    sqlite_sql = @gen.create_table(td, @sqlite)

    assert_includes pg_sql, '"id" serial PRIMARY KEY'
    assert_includes mysql_sql, "`id` int AUTO_INCREMENT PRIMARY KEY"
    assert_includes sqlite_sql, '"id" INTEGER PRIMARY KEY AUTOINCREMENT'
  end

  test "unknown column type raises" do
    assert_raises(HakumiORM::Error) { @gen.column_type_sql(:imaginary, @pg) }
  end

  test "unknown PK type raises" do
    td = HakumiORM::Migration::TableDefinition.new("bad", id: :unknown_pk)

    assert_raises(HakumiORM::Error) { @gen.create_table(td, @pg) }
  end

  test "add_index uses dialect quoting for MySQL" do
    sql = @gen.add_index("users", ["email"], unique: true, dialect: @mysql)

    assert_includes sql, "`users`"
    assert_includes sql, "`email`"
    refute_includes sql, '"users"'
  end

  test "add_index uses dialect quoting for PG" do
    sql = @gen.add_index("users", ["email"], unique: false, dialect: @pg)

    assert_includes sql, '"users"'
    assert_includes sql, '"email"'
  end

  test "remove_index uses dialect quoting for MySQL" do
    sql = @gen.remove_index("users", ["email"], dialect: @mysql)

    refute_includes sql, '"'
  end

  test "add_foreign_key constraint name uses dialect quoting for MySQL" do
    sql = @gen.add_foreign_key("posts", "users", column: "user_id", dialect: @mysql)

    assert_includes sql, "ALTER TABLE `posts`"
    assert_includes sql, "FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)"
    refute_includes sql, '"posts"'
  end

  test "remove_foreign_key constraint name uses dialect quoting for MySQL" do
    sql = @gen.remove_foreign_key("posts", "users", dialect: @mysql, column: "user_id")

    assert_includes sql, "ALTER TABLE `posts`"
    refute_includes sql, '"posts"'
  end

  test "auto-generated index name exceeding 63 chars raises on PG" do
    long_table = "a" * 30
    long_col = "b" * 30

    err = assert_raises(HakumiORM::Error) do
      @gen.add_index(long_table, [long_col], dialect: @pg)
    end

    assert_includes err.message, "exceeds"
  end

  test "auto-generated FK name exceeding 63 chars raises on PG" do
    long_table = "a" * 30
    long_col = "b" * 30

    err = assert_raises(HakumiORM::Error) do
      @gen.add_foreign_key(long_table, "users", column: long_col, dialect: @pg)
    end

    assert_includes err.message, "exceeds"
  end

  test "explicit short name bypasses length check" do
    long_table = "a" * 30
    long_col = "b" * 30

    sql = @gen.add_index(long_table, [long_col], dialect: @pg, name: "idx_short")

    assert_includes sql, '"idx_short"'
  end

  test "MySQL identifier limit is 64 chars" do
    short_name = "x" * 63
    sql = @gen.add_index("t", ["c"], dialect: @mysql, name: short_name)

    assert_includes sql, short_name

    long_name = "x" * 65

    assert_raises(HakumiORM::Error) do
      @gen.add_index("t", ["c"], dialect: @mysql, name: long_name)
    end
  end

  test "default values are raw SQL literals" do
    col = HakumiORM::Migration::ColumnDefinition.new(
      name: "created_at", type: :timestamp, null: false, default: "NOW()"
    )
    sql = @gen.add_column("users", col, @pg)

    assert_includes sql, "DEFAULT NOW()"
  end

  test "create_table with composite primary key via primary_key option" do
    td = HakumiORM::Migration::TableDefinition.new("user_roles", id: false)
    td.integer "user_id", null: false
    td.integer "role_id", null: false
    td.primary_key %w[user_id role_id]

    sql = @gen.create_table(td, @pg)

    assert_includes sql, 'PRIMARY KEY ("user_id", "role_id")'
    refute_includes sql, "bigserial"
  end

  test "create_table with composite primary key on MySQL" do
    td = HakumiORM::Migration::TableDefinition.new("user_roles", id: false)
    td.integer "user_id", null: false
    td.integer "role_id", null: false
    td.primary_key %w[user_id role_id]

    sql = @gen.create_table(td, @mysql)

    assert_includes sql, "PRIMARY KEY (`user_id`, `role_id`)"
  end
end
