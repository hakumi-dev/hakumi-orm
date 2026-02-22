# typed: false
# frozen_string_literal: true

require "test_helper"

class TestRawExprEdge < HakumiORM::TestCase
  def setup
    @compiler = HakumiORM::SqlCompiler.new(HakumiORM::Dialect::Postgresql.new)
    @id_field = HakumiORM::FieldRef.new(:id, "events", "id", '"events"."id"')
  end

  test "RawExpr basic replacement maps ? to sequential bind markers" do
    expr = HakumiORM::RawExpr.new(
      "age > ? AND email LIKE ?",
      [HakumiORM::IntBind.new(18), HakumiORM::StrBind.new("%@test.com")]
    )

    compiled = @compiler.select(table: "events", columns: [@id_field], where_expr: expr)

    assert_includes compiled.sql, "$1"
    assert_includes compiled.sql, "$2"
    assert_equal 2, compiled.binds.length
  end

  test "RawExpr raises when more ? than binds" do
    err = assert_raises(ArgumentError) do
      HakumiORM::RawExpr.new("a = ? AND b = ?", [HakumiORM::IntBind.new(1)])
    end

    assert_includes err.message, "placeholder count (2)"
    assert_includes err.message, "bind count (1)"
  end

  test "RawExpr raises when fewer ? than binds" do
    err = assert_raises(ArgumentError) do
      HakumiORM::RawExpr.new("a = ?", [HakumiORM::IntBind.new(1), HakumiORM::IntBind.new(2)])
    end

    assert_includes err.message, "placeholder count (1)"
    assert_includes err.message, "bind count (2)"
  end

  test "RawExpr with ? inside string literal requires matching bind count (known limitation)" do
    err = assert_raises(ArgumentError) do
      HakumiORM::RawExpr.new(
        "data::text = '{\"key\": \"value?\"}' AND status = ?",
        [HakumiORM::StrBind.new("active")]
      )
    end

    assert_includes err.message, "placeholder count (2)"
    assert_includes err.message, "bind count (1)"
  end
end
