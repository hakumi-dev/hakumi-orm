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

  test "distinct adds DISTINCT to the SQL" do
    UserRecord.all.distinct.to_a(adapter: @adapter)

    assert_match(/\ASELECT DISTINCT /, @adapter.last_sql)
  end

  test "distinct is chainable with where" do
    UserRecord.all.where(UserSchema::ACTIVE.eq(true)).distinct.to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "DISTINCT"
    assert_includes @adapter.last_sql, "WHERE"
  end

  test "group adds GROUP BY to the SQL" do
    UserRecord.all.group(UserSchema::ACTIVE).to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "GROUP BY"
  end

  test "having adds HAVING clause after GROUP BY" do
    UserRecord.all
              .group(UserSchema::ACTIVE)
              .having(UserSchema::AGE.gt(1))
              .to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "GROUP BY"
    assert_includes sql, "HAVING"
    group_pos = sql.index("GROUP BY")
    having_pos = sql.index("HAVING")

    assert_operator group_pos, :<, having_pos
  end

  test "lock appends FOR UPDATE" do
    UserRecord.all.lock.to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "FOR UPDATE"
  end

  test "lock with custom clause" do
    UserRecord.all.lock("FOR SHARE").to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "FOR SHARE"
  end

  test "sum returns string value from adapter" do
    @adapter.stub_default([["150"]])

    result = UserRecord.all.sum(UserSchema::AGE, adapter: @adapter)

    assert_equal "150", result
    assert_includes @adapter.last_sql, "SUM"
  end

  test "average returns string value" do
    @adapter.stub_default([["30.5"]])

    result = UserRecord.all.average(UserSchema::AGE, adapter: @adapter)

    assert_equal "30.5", result
    assert_includes @adapter.last_sql, "AVG"
  end

  test "minimum returns string value" do
    @adapter.stub_default([["18"]])

    result = UserRecord.all.minimum(UserSchema::AGE, adapter: @adapter)

    assert_equal "18", result
    assert_includes @adapter.last_sql, "MIN"
  end

  test "maximum returns string value" do
    @adapter.stub_default([["65"]])

    result = UserRecord.all.maximum(UserSchema::AGE, adapter: @adapter)

    assert_equal "65", result
    assert_includes @adapter.last_sql, "MAX"
  end

  test "sum with where filters rows" do
    @adapter.stub_default([["100"]])

    UserRecord.where(UserSchema::ACTIVE.eq(true)).sum(UserSchema::AGE, adapter: @adapter)

    assert_includes @adapter.last_sql, "SUM"
    assert_includes @adapter.last_sql, "WHERE"
  end

  test "pluck returns arrays of column values" do
    @adapter.stub_default([["Alice", "a@b.com"], ["Bob", "b@c.com"]])

    rows = UserRecord.all.pluck(UserSchema::NAME, UserSchema::EMAIL, adapter: @adapter)

    assert_equal [["Alice", "a@b.com"], ["Bob", "b@c.com"]], rows
  end

  test "pluck respects where clause" do
    @adapter.stub_default([["Alice"]])

    UserRecord.where(UserSchema::ACTIVE.eq(true)).pluck(UserSchema::NAME, adapter: @adapter)

    assert_includes @adapter.last_sql, "WHERE"
  end

  test "where_raw adds raw SQL fragment to query" do
    UserRecord.all
              .where_raw("LENGTH(\"users\".\"name\") > ?", [HakumiORM::IntBind.new(5)])
              .to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "LENGTH"
    assert_includes @adapter.last_sql, "$1"
  end

  test "where_raw chains with normal where" do
    UserRecord.all
              .where(UserSchema::ACTIVE.eq(true))
              .where_raw("\"users\".\"age\" > ?", [HakumiORM::IntBind.new(18)])
              .to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "AND"
    assert_includes sql, "$1"
    assert_includes sql, "$2"
  end

  test "compile returns CompiledQuery from dialect" do
    compiled = UserRecord.all.where(UserSchema::AGE.gt(18)).compile(@adapter.dialect)

    assert_instance_of HakumiORM::CompiledQuery, compiled
    assert_includes compiled.sql, "$1"
  end

  test "PreloadNode.from_specs converts flat symbols" do
    nodes = HakumiORM::PreloadNode.from_specs(%i[posts comments])

    assert_equal 2, nodes.length
    assert_equal :posts, nodes[0].name
    assert_empty nodes[0].children
    assert_equal :comments, nodes[1].name
  end

  test "PreloadNode.from_specs converts hash with symbol value" do
    nodes = HakumiORM::PreloadNode.from_specs([{ posts: :comments }])

    assert_equal 1, nodes.length
    assert_equal :posts, nodes[0].name
    assert_equal 1, nodes[0].children.length
    assert_equal :comments, nodes[0].children[0].name
  end

  test "PreloadNode.from_specs converts hash with array value" do
    nodes = HakumiORM::PreloadNode.from_specs([{ posts: %i[comments tags] }])

    assert_equal 1, nodes.length
    assert_equal :posts, nodes[0].name
    assert_equal 2, nodes[0].children.length
    assert_equal :comments, nodes[0].children[0].name
    assert_equal :tags, nodes[0].children[1].name
  end

  test "PreloadNode.from_specs handles mixed specs" do
    nodes = HakumiORM::PreloadNode.from_specs([:author, { posts: :comments }])

    assert_equal 2, nodes.length
    assert_equal :author, nodes[0].name
    assert_empty nodes[0].children
    assert_equal :posts, nodes[1].name
    assert_equal 1, nodes[1].children.length
  end

  test "preload accepts nested hash syntax" do
    rel = UserRecord.all.preload(posts: :comments)

    assert_instance_of UserRelation, rel
  end

  test "or merges two relations WHERE clauses with OR" do
    left = UserRecord.where(UserSchema::ACTIVE.eq(true))
    right = UserRecord.where(UserSchema::AGE.gt(65))

    left.or(right).to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "OR"
    assert_includes sql, '"users"."active"'
    assert_includes sql, '"users"."age"'
    assert_equal ["t", 65], @adapter.last_params
  end

  test "or with empty left uses right WHERE" do
    left = UserRecord.all
    right = UserRecord.where(UserSchema::ACTIVE.eq(true))

    left.or(right).to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "WHERE"
    assert_includes @adapter.last_sql, '"users"."active"'
    refute_includes @adapter.last_sql, "OR"
  end

  test "or with empty right keeps left WHERE" do
    left = UserRecord.where(UserSchema::ACTIVE.eq(true))
    right = UserRecord.all

    left.or(right).to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "WHERE"
    refute_includes @adapter.last_sql, "OR"
  end

  test "or is chainable with further where" do
    UserRecord
      .where(UserSchema::ACTIVE.eq(true))
      .or(UserRecord.where(UserSchema::AGE.gt(65)))
      .where(UserSchema::NAME.like("A%"))
      .to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "OR"
    assert_includes sql, "AND"
  end

  test "where_not negates the expression" do
    UserRecord.all.where_not(UserSchema::ACTIVE.eq(true)).to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "NOT"
    assert_includes sql, '"users"."active"'
  end

  test "where_not chains with where using AND" do
    UserRecord
      .where(UserSchema::AGE.gt(18))
      .where_not(UserSchema::ACTIVE.eq(false))
      .to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "AND"
    assert_includes sql, "NOT"
  end

  test "as_json returns hash with string keys" do
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    h = user.as_json

    assert_equal "Alice", h["name"]
    assert_equal 1, h["id"]
    assert_equal 25, h["age"]
    assert h["active"]
    assert_equal 5, h.keys.length
  end

  test "as_json only filters to specified columns" do
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    h = user.as_json(only: %i[id name])

    assert_equal({ "id" => 1, "name" => "Alice" }, h)
  end

  test "as_json except excludes specified columns" do
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    h = user.as_json(except: %i[age active])

    assert_equal %w[email id name], h.keys.sort
  end

  test "as_json preserves nil for nullable columns" do
    user = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: nil, active: true)
    h = user.as_json

    assert_nil h["age"]
  end

  test "scope method on Relation generates correct WHERE" do
    UserRecord.all.active.to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, '"users"."active"'
    assert_equal ["t"], @adapter.last_params
  end

  test "scopes chain together producing AND" do
    UserRecord.all.active.older_than(18).to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, "AND"
    assert_includes sql, '"users"."active"'
    assert_includes sql, '"users"."age"'
    assert_equal ["t", 18], @adapter.last_params
  end

  test "scopes chain with where and order" do
    UserRecord
      .where(UserSchema::NAME.like("A%"))
      .active
      .older_than(21)
      .order(UserSchema::NAME.asc)
      .limit(10)
      .to_a(adapter: @adapter)

    sql = @adapter.last_sql

    assert_includes sql, '"users"."name" LIKE'
    assert_includes sql, '"users"."active"'
    assert_includes sql, '"users"."age"'
    assert_includes sql, "ORDER BY"
    assert_includes sql, "LIMIT 10"
  end

  test "scope returns same relation type for continued chaining" do
    rel = UserRecord.all.active

    assert_instance_of UserRelation, rel
  end

  test "changed_from? returns false for identical records" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    b = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    refute a.changed_from?(b)
  end

  test "changed_from? returns true when any field differs" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    b = UserRecord.new(id: 1, name: "Bob", email: "a@b.com", age: 25, active: true)

    assert a.changed_from?(b)
  end

  test "diff returns empty hash for identical records" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    b = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)

    assert_empty a.diff(b)
  end

  test "diff returns changed fields with old and new values" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    b = UserRecord.new(id: 1, name: "Bob", email: "b@c.com", age: 25, active: true)

    d = a.diff(b)

    assert_equal 2, d.length
    assert_equal %w[Alice Bob], d[:name]
    assert_equal ["a@b.com", "b@c.com"], d[:email]
    refute d.key?(:id)
    refute d.key?(:age)
  end

  test "diff detects nil to value change" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: nil, active: true)
    b = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)

    d = a.diff(b)

    assert_equal [nil, 30], d[:age]
  end

  test "diff detects value to nil change" do
    a = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true)
    b = UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: nil, active: true)

    d = a.diff(b)

    assert_equal [25, nil], d[:age]
  end

  test "to_a raises when select narrows columns" do
    err = assert_raises(HakumiORM::Error) do
      UserRecord.all.select(UserSchema::ID, UserSchema::NAME).to_a(adapter: @adapter)
    end

    assert_includes err.message, "Cannot hydrate records with a partial column set"
  end

  test "first raises when select narrows columns" do
    assert_raises(HakumiORM::Error) do
      UserRecord.all.select(UserSchema::ID).first(adapter: @adapter)
    end
  end

  test "find_each raises when select narrows columns" do
    assert_raises(HakumiORM::Error) do
      UserRecord.all.select(UserSchema::ID).find_each(adapter: @adapter, &:id)
    end
  end

  test "select does not raise for pluck_raw" do
    @adapter.stub_default([["Alice"], ["Bob"]])

    result = UserRecord.all.select(UserSchema::NAME).pluck_raw(UserSchema::NAME, adapter: @adapter)

    assert_equal 2, result.length
  end

  test "select does not raise for to_sql" do
    compiled = UserRecord.all.select(UserSchema::ID, UserSchema::NAME).to_sql(adapter: @adapter)

    assert_includes compiled.sql, "SELECT"
  end
end
