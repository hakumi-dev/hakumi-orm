# typed: false
# frozen_string_literal: true

require "test_helper"

class TestDialectPostgresql < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
  end

  test "bind_marker returns 1-indexed $N markers" do
    assert_equal "$1", @dialect.bind_marker(0)
    assert_equal "$2", @dialect.bind_marker(1)
    assert_equal "$100", @dialect.bind_marker(99)
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

  test "supports_ddl_transactions? returns true" do
    assert_predicate @dialect, :supports_ddl_transactions?
  end

  test "supports_advisory_lock? returns true" do
    assert_predicate @dialect, :supports_advisory_lock?
  end

  test "advisory_lock_sql uses pg_advisory_lock" do
    assert_includes @dialect.advisory_lock_sql, "pg_advisory_lock"
    assert_includes @dialect.advisory_unlock_sql, "pg_advisory_unlock"
  end
end
