# typed: false
# frozen_string_literal: true

require "test_helper"

class TestDialectPostgresql < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
  end

  test "bind_marker is 1-indexed (PG uses $1, $2, ...)" do
    assert_equal "$1", @dialect.bind_marker(0)
    assert_equal "$2", @dialect.bind_marker(1)
    assert_equal "$100", @dialect.bind_marker(99)
  end

  test "quote_id wraps identifiers in double quotes to prevent SQL injection" do
    assert_equal '"users"', @dialect.quote_id("users")
    assert_equal '"order"', @dialect.quote_id("order")
  end

  test "quote_id caches results to avoid repeated string allocation" do
    result1 = @dialect.quote_id("users")
    result2 = @dialect.quote_id("users")

    assert_same result1, result2
  end

  test "qualified_name produces fully-qualified column reference" do
    assert_equal '"users"."name"', @dialect.qualified_name("users", "name")
  end
end
