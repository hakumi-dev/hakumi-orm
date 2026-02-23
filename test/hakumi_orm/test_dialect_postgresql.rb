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

  test "encode_boolean produces PG t/f format" do
    assert_equal "t", @dialect.encode_boolean(true)
    assert_equal "f", @dialect.encode_boolean(false)
  end

  test "cast_boolean interprets PG t/f format" do
    assert @dialect.cast_boolean("t")
    refute @dialect.cast_boolean("f")
  end

  test "encode_time produces UTC timestamp string with microseconds" do
    t = Time.utc(2025, 6, 15, 9, 30, 0, 123_456)
    result = @dialect.encode_time(t)

    assert_equal "2025-06-15 09:30:00.123456", result
  end

  test "cast_time parses timestamp and returns UTC" do
    result = @dialect.cast_time("2025-06-15 09:30:00.123456")

    assert_instance_of Time, result
    assert_predicate result, :utc?
    assert_equal 123_456, result.usec
  end

  test "encode_decimal produces string representation" do
    assert_equal "99.99", @dialect.encode_decimal(BigDecimal("99.99"))
  end

  test "cast_decimal returns BigDecimal" do
    result = @dialect.cast_decimal("99.99")

    assert_instance_of BigDecimal, result
    assert_equal BigDecimal("99.99"), result
  end

  test "cast_integer returns integer" do
    assert_equal 42, @dialect.cast_integer("42")
    assert_equal(-5, @dialect.cast_integer("-5"))
  end

  test "cast_float returns float" do
    assert_in_delta 3.14, @dialect.cast_float("3.14")
  end

  test "cast_date returns Date" do
    result = @dialect.cast_date("2025-06-15")

    assert_instance_of Date, result
    assert_equal 2025, result.year
  end

  test "encode_date produces ISO 8601" do
    assert_equal "2025-06-15", @dialect.encode_date(Date.new(2025, 6, 15))
  end

  test "cast_int_array parses PG array literal" do
    assert_equal [1, 2, 3], @dialect.cast_int_array("{1,2,3}")
  end

  test "encode_int_array produces PG array literal" do
    assert_equal "{1,2,3}", @dialect.encode_int_array([1, 2, 3])
  end

  test "cast_bool_array parses PG boolean array" do
    assert_equal [true, false, nil], @dialect.cast_bool_array("{t,f,NULL}")
  end

  test "encode_bool_array produces PG boolean array literal" do
    assert_equal "{t,f}", @dialect.encode_bool_array([true, false])
  end
end
