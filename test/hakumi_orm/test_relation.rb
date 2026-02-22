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

  # -- reload! ----------------------------------------------------------------

  test "reload! re-fetches the record by pk" do
    @adapter.stub_default([["1", "UpdatedAlice", "a@b.com", "30", "t"]])
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    reloaded = user.reload!(adapter: @adapter)

    assert_instance_of UserRecord, reloaded
    assert_equal "UpdatedAlice", reloaded.name
    assert_equal 30, reloaded.age
  end

  test "reload! raises Error when record not found" do
    @adapter.stub_default([])
    user = UserRecord.new(id: 999, name: "Ghost", email: "g@b.com", age: nil, active: false)

    assert_raises(HakumiORM::Error) { user.reload!(adapter: @adapter) }
  end

  # -- update! ----------------------------------------------------------------

  test "update! executes UPDATE with all columns and returns new record" do
    @adapter.stub_default([["1", "Bob", "a@b.com", "25", "t"]])
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    updated = user.update!(name: "Bob", adapter: @adapter)

    assert_instance_of UserRecord, updated
    assert_equal "Bob", updated.name
    assert_includes @adapter.last_sql, "UPDATE"
    assert_includes @adapter.last_sql, "SET"
    assert_includes @adapter.last_sql, "RETURNING"
  end

  test "update! defaults unchanged fields to current values" do
    @adapter.stub_default([["1", "Alice", "a@b.com", "25", "f"]])
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    updated = user.update!(active: false, adapter: @adapter)

    assert_equal "Alice", updated.name
    refute updated.active
  end

  test "update! runs on_update contract and raises on failure" do
    UserRecord::Contract.define_singleton_method(:on_update) do |record, e|
      e.add(:name, "cannot be blank") if record.name.strip.empty?
    end

    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    err = assert_raises(HakumiORM::ValidationError) { user.update!(name: "", adapter: @adapter) }
    assert_includes err.errors.messages[:name], "cannot be blank"
  ensure
    sc = UserRecord::Contract.singleton_class
    sc.remove_method(:on_update) if sc.method_defined?(:on_update, false)
  end

  test "update! raises Error when UPDATE returns no rows" do
    @adapter.stub_default([])
    user = UserRecord.new(id: 999, name: "Alice", email: "a@b.com", age: nil, active: true)

    assert_raises(HakumiORM::Error) { user.update!(name: "Bob", adapter: @adapter) }
  end

  # -- delete! ----------------------------------------------------------------

  test "delete! executes DELETE with pk bind and raises on zero affected rows" do
    @adapter.stub_default([], affected: 1)
    user = UserRecord.new(id: 42, name: "Alice", email: "a@b.com", age: nil, active: true)

    user.delete!(adapter: @adapter)

    assert_includes @adapter.last_sql, 'DELETE FROM "users"'
    assert_includes @adapter.last_sql, "$1"
    assert_equal [42], @adapter.last_params
  end

  test "delete! raises Error when no rows affected" do
    @adapter.stub_default([], affected: 0)
    user = UserRecord.new(id: 999, name: "Ghost", email: "g@b.com", age: nil, active: false)

    assert_raises(HakumiORM::Error) { user.delete!(adapter: @adapter) }
  end

  # -- exists? ----------------------------------------------------------------

  test "exists? returns true when rows match" do
    @adapter.stub_default([["1"]])

    assert UserRecord.exists?(UserSchema::ACTIVE.eq(true), adapter: @adapter)
    assert_includes @adapter.last_sql, "SELECT 1"
    assert_includes @adapter.last_sql, "LIMIT 1"
  end

  test "exists? returns false when no rows match" do
    @adapter.stub_default([])

    refute UserRecord.exists?(UserSchema::ACTIVE.eq(true), adapter: @adapter)
  end

  test "exists? on relation respects where clauses" do
    @adapter.stub_default([["1"]])

    result = UserRecord.where(UserSchema::AGE.gt(18)).exists?(adapter: @adapter)

    assert result
    assert_includes @adapter.last_sql, "WHERE"
  end

  # -- find_by ----------------------------------------------------------------

  test "find_by returns first matching record" do
    @adapter.stub_default([["1", "Alice", "a@b.com", "25", "t"]])

    user = UserRecord.find_by(UserSchema::EMAIL.eq("a@b.com"), adapter: @adapter)

    assert_instance_of UserRecord, user
    assert_equal "Alice", user.name
    assert_includes @adapter.last_sql, "LIMIT 1"
  end

  test "find_by returns nil when no match" do
    @adapter.stub_default([])

    assert_nil UserRecord.find_by(UserSchema::EMAIL.eq("nope"), adapter: @adapter)
  end

  # -- to_h -------------------------------------------------------------------

  test "to_h returns hash with all column values keyed by name" do
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    h = user.to_h

    assert_equal({ id: 1, name: "Alice", email: "a@b.com", age: 25, active: true }, h)
  end

  test "to_h preserves nil values for nullable columns" do
    user = UserRecord.new(id: 2, name: "Bob", email: "b@c.com", age: nil, active: false)
    h = user.to_h

    assert_nil h[:age]
    refute h[:active]
  end
end
