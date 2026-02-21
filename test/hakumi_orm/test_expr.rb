# typed: false
# frozen_string_literal: true

require "test_helper"

class TestExpr < HakumiORM::TestCase
  test "and produces deterministic parentheses in SQL" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = UserSchema::AGE.gt(18).and(UserSchema::ACTIVE.eq(true))
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '("users"."age" > $1 AND "users"."active" = $2)'
  end

  test "or produces deterministic parentheses in SQL" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = UserSchema::AGE.lt(18).or(UserSchema::AGE.gt(65))
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '("users"."age" < $1 OR "users"."age" > $2)'
  end

  test "nested OR inside AND gets correct parentheses" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    inner = UserSchema::AGE.lt(18).or(UserSchema::AGE.gt(65))
    expr = UserSchema::ACTIVE.eq(true).and(inner)
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '("users"."active" = $1 AND ("users"."age" < $2 OR "users"."age" > $3))'
  end

  test "not wraps expression with NOT keyword" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = UserSchema::ACTIVE.eq(true).not
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, 'NOT ("users"."active" = $1)'
  end

  test "chained and is left-associative" do
    a = UserSchema::AGE.gt(18)
    b = UserSchema::NAME.eq("Bob")
    c = UserSchema::ACTIVE.eq(true)
    expr = a.and(b).and(c)

    assert_instance_of HakumiORM::AndExpr, expr.left
    assert_instance_of HakumiORM::Predicate, expr.right
  end

  test "operator & compiles identical SQL to .and" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = (UserSchema::AGE > 18) & (UserSchema::ACTIVE == true)
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '("users"."age" > $1 AND "users"."active" = $2)'
  end

  test "operator | and ! compose into NOT (a OR b)" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = !((UserSchema::AGE < 18) | (UserSchema::AGE > 65))
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, 'NOT (("users"."age" < $1 OR "users"."age" > $2))'
  end

  test "!= operator compiles to SQL <>" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = UserSchema::NAME != "temp"
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '"users"."name" <> $1'
    assert_equal "temp", q.binds[0].value
  end

  test "operators and methods interop in the same expression" do
    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    expr = (UserSchema::AGE >= 18).and(UserSchema::EMAIL.like("%@co.jp"))
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_includes q.sql, '("users"."age" >= $1 AND "users"."email" LIKE $2)'
  end

  test "deeply nested expressions compile without error" do
    expr = UserSchema::AGE.gt(1)
    50.times { |i| expr = expr.and(UserSchema::AGE.lt(100 + i)) }

    compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    q = compiler.select(table: "users", columns: [UserSchema::ID], where_expr: expr)

    assert_equal 51, q.binds.length
    assert_includes q.sql, "$51"
  end
end
