# typed: false
# frozen_string_literal: true

require "test_helper"

class TestDialectSqlite < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Sqlite.new
  end

  test "bind_marker returns ? for all positions" do
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

  test "qualified_name produces double-quoted table.column reference" do
    assert_equal '"users"."name"', @dialect.qualified_name("users", "name")
  end

  test "supports_returning? returns true" do
    assert_predicate @dialect, :supports_returning?
  end

  test "name returns :sqlite" do
    assert_equal :sqlite, @dialect.name
  end

  test "supports_ddl_transactions? returns true" do
    assert_predicate @dialect, :supports_ddl_transactions?
  end

  test "supports_advisory_lock? returns false" do
    refute_predicate @dialect, :supports_advisory_lock?
  end

  test "advisory_lock_sql and advisory_unlock_sql return nil" do
    assert_nil @dialect.advisory_lock_sql
    assert_nil @dialect.advisory_unlock_sql
  end
end
