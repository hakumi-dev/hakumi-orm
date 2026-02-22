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

  test "where returns the same object, not a copy" do
    base = UserRecord.all
    returned = base.where(UserSchema::ACTIVE.eq(true))

    assert_same base, returned
  end

  test "branching from a stored base contaminates the original" do
    base = UserRecord.all
    base.where(UserSchema::ACTIVE.eq(true))
    base.where(UserSchema::AGE.gt(30))
    base.to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, '"users"."active"'
    assert_includes sql, '"users"."age"'
  end

  test "two branches from the same base share state" do
    base = UserRecord.all
    _a = base.where(UserSchema::ACTIVE.eq(true))
    _b = base.where(UserSchema::AGE.gt(18))

    base.to_a(adapter: @adapter)
    sql = @adapter.last_sql

    assert_includes sql, '"users"."active"', "first branch leaked into base"
    assert_includes sql, '"users"."age"', "second branch also leaked into base"
  end

  test "dup creates an independent copy that does not share arrays" do
    base = UserRecord.all
    copy = base.dup
    copy.where(UserSchema::ACTIVE.eq(true))
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

  test "find_in_batches emits DECLARE CURSOR regardless of dialect" do
    mysql_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Mysql.new)

    UserRecord.all.find_in_batches(adapter: mysql_adapter) { |_| break }

    cursor_sql = mysql_adapter.executed_queries.find { |q| q[:sql].include?("DECLARE") }

    assert cursor_sql, "find_in_batches emits PG-only DECLARE CURSOR even on MySQL dialect"
  end
end
