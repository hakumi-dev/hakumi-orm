# typed: false
# frozen_string_literal: true

require "test_helper"

class TestCast < HakumiORM::TestCase
  test "to_integer handles negative and zero" do
    assert_equal(-5, HakumiORM::Cast.to_integer("-5"))
    assert_equal 0, HakumiORM::Cast.to_integer("0")
  end

  test "to_decimal preserves arbitrary precision" do
    result = HakumiORM::Cast.to_decimal("123456789.123456789")

    assert_instance_of BigDecimal, result
    assert_equal BigDecimal("123456789.123456789"), result
  end

  test "to_boolean only treats PG t as true" do
    assert HakumiORM::Cast.to_boolean("t")
    refute HakumiORM::Cast.to_boolean("f")
    refute HakumiORM::Cast.to_boolean("true")
    refute HakumiORM::Cast.to_boolean("1")
  end

  test "to_time parses PG timestamp with microseconds and returns UTC" do
    result = HakumiORM::Cast.to_time("2024-01-15 10:30:45.123456")

    assert_instance_of Time, result
    assert_predicate result, :utc?
    assert_equal 45, result.sec
    assert_equal 123_456, result.usec
  end

  test "to_date parses PG date format" do
    result = HakumiORM::Cast.to_date("2024-12-31")

    assert_equal 2024, result.year
    assert_equal 12, result.month
    assert_equal 31, result.day
  end

  test "to_float handles scientific notation" do
    assert_in_delta 1.5e10, HakumiORM::Cast.to_float("1.5e10")
  end

  test "to_json parses JSON object string" do
    result = HakumiORM::Cast.to_json('{"key":"value","num":42}')

    assert_instance_of HakumiORM::Json, result
    assert_equal "value", result["key"]&.as_s
    assert_equal 42, result["num"]&.as_i
  end

  test "to_json parses JSON array string" do
    result = HakumiORM::Cast.to_json("[1,2,3]")

    assert_instance_of HakumiORM::Json, result
    assert_equal 1, result.at(0)&.as_i
    assert_equal 3, result.at(2)&.as_i
  end
end
