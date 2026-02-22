# typed: false
# frozen_string_literal: true

require "test_helper"

class TestRelation < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @prev_adapter = HakumiORM.config.adapter
    HakumiORM.adapter = @adapter
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
  end

  test "to_a hydrates typed UserRecord objects from raw string rows" do
    @adapter.stub_default([["1", "Alice", "a@b.com", "25", "t"],
                           ["2", "Bob", "b@c.com", nil, "f"]])

    users = UserRecord.all.to_a(adapter: @adapter)

    assert_equal 2, users.length
    assert_instance_of UserRecord, users[0]
    assert_equal 1, users[0].id
    assert_equal "Alice", users[0].name
    assert_equal 25, users[0].age
    assert users[0].active
    assert_nil users[1].age
    refute users[1].active
  end

  test "to_a returns empty array when no rows match" do
    @adapter.stub_default([])
    users = UserRecord.all.to_a(adapter: @adapter)

    assert_empty users
  end

  test "where, order, limit, offset all return the same relation instance" do
    rel = UserRecord.all
                    .where(UserSchema::AGE.gt(18))
                    .order(UserSchema::NAME.asc)
                    .limit(10)
                    .offset(5)

    assert_instance_of UserRelation, rel
  end

  test "first returns a single typed object or nil" do
    @adapter.stub_default([["1", "Alice", "a@b.com", "25", "t"]])

    assert_instance_of UserRecord, UserRecord.all.first(adapter: @adapter)
  end

  test "first returns nil on empty result" do
    @adapter.stub_default([])

    assert_nil UserRecord.all.first(adapter: @adapter)
  end

  test "first uses LIMIT 1 in the SQL" do
    UserRecord.all.first(adapter: @adapter)

    assert_includes @adapter.last_sql, "LIMIT 1"
  end

  test "count parses COUNT(*) result as integer" do
    @adapter.stub_default([["42"]])

    assert_equal 42, UserRecord.all.count(adapter: @adapter)
    assert_includes @adapter.last_sql, "COUNT(*)"
  end

  test "count without WHERE uses prepared statement path" do
    @adapter.stub_result("COUNT(*)", [["99"]])

    result = UserRecord.all.count(adapter: @adapter)

    assert_equal 99, result
  end

  test "count with WHERE falls back to dynamic SQL" do
    @adapter.stub_default([["5"]])

    result = UserRecord.where(UserSchema::ACTIVE.eq(true)).count(adapter: @adapter)

    assert_equal 5, result
    assert_includes @adapter.last_sql, "WHERE"
  end

  test "multiple where calls are combined with AND" do
    UserRecord.all
              .where(UserSchema::AGE.gt(18))
              .where(UserSchema::ACTIVE.eq(true))
              .to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "AND"
    assert_equal [18, "t"], @adapter.last_params
  end

  test "to_sql returns CompiledQuery without hitting the adapter" do
    compiled = UserRecord.where(UserSchema::AGE.gt(18)).to_sql(adapter: @adapter)

    assert_instance_of HakumiORM::CompiledQuery, compiled
    assert_includes compiled.sql, "$1"
    assert_empty @adapter.executed_queries
  end

  test "full query: where with AND, order, limit generates correct SQL and binds" do
    @adapter.stub_default([["1", "Alice", "a@gmail.com", "25", "t"]])

    users = UserRecord
            .where(UserSchema::AGE.gt(18).and(UserSchema::EMAIL.like("%@gmail.com")))
            .order(UserSchema::NAME.asc)
            .limit(10)
            .to_a(adapter: @adapter)

    assert_equal 1, users.length

    sql = @adapter.last_sql

    assert_includes sql, '"users"."age" > $1'
    assert_includes sql, '"users"."email" LIKE $2'
    assert_includes sql, "ORDER BY"
    assert_includes sql, "LIMIT 10"
    assert_equal [18, "%@gmail.com"], @adapter.last_params
  end

  test "OR query generates correct parenthesized SQL" do
    UserRecord.where(
      UserSchema::AGE.lt(18).or(UserSchema::AGE.gt(65))
    ).to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "OR"
    assert_equal [18, 65], @adapter.last_params
  end
end
