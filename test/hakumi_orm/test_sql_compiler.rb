# typed: false
# frozen_string_literal: true

require "test_helper"

class TestSqlCompiler < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
    @compiler = HakumiORM::SqlCompiler.new(@dialect)
  end

  test "values appear as bind markers, never inline in the SQL" do
    expr = UserSchema::NAME.eq("Robert'); DROP TABLE users;--")
    q = @compiler.select(table: "users", columns: UserSchema::ALL, where_expr: expr)

    refute_includes q.sql, "Robert"
    refute_includes q.sql, "DROP"
    assert_includes q.sql, "$1"
    assert_equal "Robert'); DROP TABLE users;--", q.pg_params[0]
  end

  test "select without where produces clean SQL with all columns" do
    q = @compiler.select(table: "users", columns: UserSchema::ALL)

    assert_match(/\ASELECT .+ FROM "users"\z/, q.sql)
    assert_empty q.binds
  end

  test "select with eq uses bind marker" do
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: UserSchema::AGE.eq(25))

    assert_includes q.sql, '"users"."age" = $1'
    assert_equal [25], q.pg_params
  end

  test "select with neq uses <>" do
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: UserSchema::AGE.neq(0))

    assert_includes q.sql, '"users"."age" <> $1'
  end

  test "select with combined AND expression" do
    expr = UserSchema::AGE.gt(18).and(UserSchema::NAME.like("%alice%"))
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "("
    assert_includes q.sql, "AND"
    assert_equal [18, "%alice%"], q.pg_params
  end

  test "select with IN produces comma-separated bind markers" do
    expr = UserSchema::AGE.in_list([18, 21, 25])
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "IN ($1, $2, $3)"
    assert_equal [18, 21, 25], q.pg_params
  end

  test "select with NOT IN" do
    expr = UserSchema::AGE.not_in_list([99, 100])
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "NOT IN ($1, $2)"
  end

  test "select with BETWEEN uses two bind markers" do
    expr = UserSchema::AGE.between(18, 65)
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "BETWEEN $1 AND $2"
    assert_equal [18, 65], q.pg_params
  end

  test "IS NULL and IS NOT NULL produce no bind markers" do
    q_null = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: UserSchema::AGE.is_null)
    q_not = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: UserSchema::AGE.is_not_null)

    assert_includes q_null.sql, "IS NULL"
    assert_empty q_null.binds
    assert_includes q_not.sql, "IS NOT NULL"
    assert_empty q_not.binds
  end

  test "ILIKE uses correct keyword" do
    expr = UserSchema::EMAIL.ilike("%@gmail.com")
    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "ILIKE $1"
  end

  test "LIMIT and OFFSET appear after WHERE and ORDER BY" do
    q = @compiler.select(
      table: "users", columns: [UserSchema::ID],
      where_expr: UserSchema::ACTIVE.eq(true),
      orders: [HakumiORM::OrderClause.new(UserSchema::NAME, :asc)],
      limit_val: 10, offset_val: 20
    )

    where_pos = q.sql.index("WHERE")
    order_pos = q.sql.index("ORDER BY")
    limit_pos = q.sql.index("LIMIT")
    offset_pos = q.sql.index("OFFSET")

    assert_operator where_pos, :<, order_pos, "WHERE should come before ORDER BY"
    assert_operator order_pos, :<, limit_pos, "ORDER BY should come before LIMIT"
    assert_operator limit_pos, :<, offset_pos, "LIMIT should come before OFFSET"
  end

  test "ORDER BY with multiple columns and directions" do
    orders = [
      HakumiORM::OrderClause.new(UserSchema::NAME, :asc),
      HakumiORM::OrderClause.new(UserSchema::AGE, :desc)
    ]
    q = @compiler.select(table: "users", columns: [UserSchema::ID], orders: orders)

    assert_includes q.sql, '"users"."name" ASC, "users"."age" DESC'
  end

  test "bind markers are sequential across complex nested expressions" do
    expr = UserSchema::AGE.gt(18)
                          .and(UserSchema::NAME.eq("Alice"))
                          .or(UserSchema::EMAIL.like("%gmail%"))

    q = @compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, "$1"
    assert_includes q.sql, "$2"
    assert_includes q.sql, "$3"
    refute_includes q.sql, "$4"
    assert_equal 3, q.binds.length
  end

  test "count generates COUNT(*) query" do
    q = @compiler.count(table: "users")

    assert_equal 'SELECT COUNT(*) FROM "users"', q.sql
  end

  test "count with where includes condition" do
    q = @compiler.count(table: "users", where_expr: UserSchema::ACTIVE.eq(true))

    assert_includes q.sql, "COUNT(*)"
    assert_includes q.sql, "WHERE"
    assert_equal 1, q.binds.length
  end

  test "delete with where produces correct SQL" do
    q = @compiler.delete(table: "users", where_expr: UserSchema::ID.eq(1))

    assert_equal 'DELETE FROM "users" WHERE "users"."id" = $1', q.sql
    assert_equal [1], q.pg_params
  end

  test "delete without where deletes all rows" do
    q = @compiler.delete(table: "users")

    assert_equal 'DELETE FROM "users"', q.sql
  end

  test "update SET binds come before WHERE binds" do
    assignments = [
      HakumiORM::Assignment.new(UserSchema::NAME, HakumiORM::StrBind.new("Bob")),
      HakumiORM::Assignment.new(UserSchema::AGE, HakumiORM::IntBind.new(30))
    ]
    q = @compiler.update(table: "users", assignments: assignments, where_expr: UserSchema::ID.eq(1))

    assert_includes q.sql, '"name" = $1, "age" = $2'
    assert_includes q.sql, 'WHERE "users"."id" = $3'
    assert_equal ["Bob", 30, 1], q.pg_params
  end

  test "insert produces correct VALUES clause" do
    cols = [UserSchema::NAME, UserSchema::EMAIL]
    vals = [[HakumiORM::StrBind.new("Alice"), HakumiORM::StrBind.new("a@b.com")]]
    q = @compiler.insert(table: "users", columns: cols, values: vals)

    assert_includes q.sql, 'INSERT INTO "users" ("name", "email") VALUES ($1, $2)'
    assert_equal ["Alice", "a@b.com"], q.pg_params
  end

  test "insert with RETURNING adds clause" do
    cols = [UserSchema::NAME]
    vals = [[HakumiORM::StrBind.new("Alice")]]
    q = @compiler.insert(table: "users", columns: cols, values: vals, returning: UserSchema::ID)

    assert_includes q.sql, 'RETURNING "id"'
  end

  test "batch insert produces sequential bind markers across rows" do
    cols = [UserSchema::NAME, UserSchema::EMAIL]
    vals = [
      [HakumiORM::StrBind.new("Alice"), HakumiORM::StrBind.new("a@b.com")],
      [HakumiORM::StrBind.new("Bob"), HakumiORM::StrBind.new("b@c.com")]
    ]
    q = @compiler.insert(table: "users", columns: cols, values: vals)

    assert_includes q.sql, "($1, $2), ($3, $4)"
    assert_equal 4, q.binds.length
  end
end
