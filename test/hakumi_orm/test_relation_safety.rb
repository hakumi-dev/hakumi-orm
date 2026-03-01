# typed: false
# frozen_string_literal: true

require "test_helper"

class TestRelationSafety < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @prev_adapter = HakumiORM.config.adapter
    HakumiORM.adapter = @adapter
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
  end

  test "all creates a new Relation instance on every call" do
    a = UserRecord.all
    b = UserRecord.all

    refute_same a, b
  end

  test "where returns a new relation, not the same object" do
    base = UserRecord.all
    returned = base.where(UserSchema::ACTIVE.eq(true))

    refute_same base, returned
  end

  test "branching from a stored base does not contaminate the original" do
    base = UserRecord.all
    _a = base.where(UserSchema::ACTIVE.eq(true))
    _b = base.where(UserSchema::AGE.gt(30))
    base.to_a(adapter: @adapter)

    refute_includes @adapter.last_sql, "WHERE"
  end

  test "two branches from the same base are independent" do
    base = UserRecord.all
    a = base.where(UserSchema::ACTIVE.eq(true))
    b = base.where(UserSchema::AGE.gt(18))

    a.to_a(adapter: @adapter)
    assert_includes @adapter.last_sql, '"users"."active" ='
    refute_includes @adapter.last_sql, '"users"."age" >'

    b.to_a(adapter: @adapter)
    assert_includes @adapter.last_sql, '"users"."age" >'
    refute_includes @adapter.last_sql, '"users"."active" ='
  end

  test "fluent methods leave the original relation unchanged" do
    base = UserRecord.all
    _copy = base.where(UserSchema::ACTIVE.eq(true))
    base.to_a(adapter: @adapter)

    refute_includes @adapter.last_sql, "WHERE"
  end

  test "dup preserves defaults_pristine flag" do
    rel = ArticleRelation.new.with_deleted
    copy = rel.dup

    @adapter.stub_default([["5"]])
    copy.count(adapter: @adapter)

    refute_includes @adapter.last_sql, "IS NULL"
  end

  test "dup of pristine relation keeps fast-path for count" do
    rel = ArticleRelation.new
    copy = rel.dup
    @adapter.stub_result("COUNT(*)", [["10"]])

    result = copy.count(adapter: @adapter)

    assert_equal 10, result
    assert_includes @adapter.last_sql, "IS NULL"
  end

  test "find_in_batches on PG uses DECLARE CURSOR" do
    pg_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Postgresql.new)

    UserRecord.all.find_in_batches(adapter: pg_adapter) { |_| break }

    cursor_sql = pg_adapter.executed_queries.find { |q| q[:sql].include?("DECLARE") }

    assert cursor_sql, "PostgreSQL should use DECLARE CURSOR"
  end

  test "find_in_batches_cursor uses adapter.transaction instead of raw BEGIN/COMMIT" do
    pg_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Postgresql.new)

    UserRecord.all.find_in_batches(adapter: pg_adapter) { |_| break }

    sqls = pg_adapter.executed_queries.map { |q| q[:sql] }

    assert_equal "BEGIN", sqls.first, "should open transaction via adapter.transaction"
    assert_includes sqls, "COMMIT"
    assert sqls.any? { |s| s.include?("CLOSE") }, "should close cursor in ensure"
  end

  test "find_in_batches_cursor inside existing transaction does not emit extra BEGIN" do
    pg_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Postgresql.new)

    pg_adapter.transaction do |_txn|
      UserRecord.all.find_in_batches(adapter: pg_adapter) { |_| break }
    end

    sqls = pg_adapter.executed_queries.map { |q| q[:sql] }
    begin_count = sqls.count { |s| s == "BEGIN" }

    assert_equal 1, begin_count, "nested cursor should not emit extra BEGIN"
  end

  test "find_in_batches on MySQL uses LIMIT/OFFSET instead of CURSOR" do
    mysql_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Mysql.new)

    UserRecord.all.find_in_batches(adapter: mysql_adapter) { |_| break }

    queries = mysql_adapter.executed_queries.map { |q| q[:sql] }

    assert queries.none? { |q| q.include?("DECLARE") }, "MySQL must not use DECLARE CURSOR"
    assert queries.none? { |q| q.include?("BEGIN") }, "MySQL LIMIT/OFFSET does not need BEGIN"
    assert queries.any? { |q| q.include?("LIMIT") }, "MySQL should use LIMIT-based batching"
  end

  test "find_in_batches on SQLite uses LIMIT/OFFSET instead of CURSOR" do
    sqlite_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Sqlite.new)

    UserRecord.all.find_in_batches(adapter: sqlite_adapter) { |_| break }

    queries = sqlite_adapter.executed_queries.map { |q| q[:sql] }

    assert queries.none? { |q| q.include?("DECLARE") }, "SQLite must not use DECLARE CURSOR"
    assert queries.any? { |q| q.include?("LIMIT") }, "SQLite should use LIMIT-based batching"
  end

  test "find_each delegates to find_in_batches on MySQL" do
    mysql_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Mysql.new)

    UserRecord.all.find_each(adapter: mysql_adapter) { |_| break }

    queries = mysql_adapter.executed_queries.map { |q| q[:sql] }

    assert queries.none? { |q| q.include?("DECLARE") }, "find_each on MySQL must not use cursors"
    assert queries.any? { |q| q.include?("LIMIT") }, "find_each on MySQL should use LIMIT"
  end
end
