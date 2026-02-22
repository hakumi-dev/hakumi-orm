# typed: false
# frozen_string_literal: true

require "test_helper"

class TestDialectSqlite < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Sqlite.new
  end

  test "bind_marker always returns ? (SQLite uses positional ? placeholders)" do
    assert_equal "?", @dialect.bind_marker(0)
    assert_equal "?", @dialect.bind_marker(1)
    assert_equal "?", @dialect.bind_marker(99)
  end

  test "quote_id wraps identifiers in double quotes" do
    assert_equal '"users"', @dialect.quote_id("users")
    assert_equal '"order"', @dialect.quote_id("order")
  end

  test "quote_id caches results" do
    result1 = @dialect.quote_id("users")
    result2 = @dialect.quote_id("users")

    assert_same result1, result2
  end

  test "qualified_name produces double-quoted column reference" do
    assert_equal '"users"."name"', @dialect.qualified_name("users", "name")
  end

  test "supports RETURNING (SQLite 3.35+)" do
    assert_predicate @dialect, :supports_returning?
  end

  test "name is :sqlite" do
    assert_equal :sqlite, @dialect.name
  end
end
