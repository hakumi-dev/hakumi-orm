# typed: false
# frozen_string_literal: true

require "test_helper"

class TestDialectMysql < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Mysql.new
  end

  test "bind_marker returns ? for all positions" do
    assert_equal "?", @dialect.bind_marker(0)
    assert_equal "?", @dialect.bind_marker(1)
    assert_equal "?", @dialect.bind_marker(99)
  end

  test "quote_id wraps identifiers in backticks" do
    assert_equal "`users`", @dialect.quote_id("users")
    assert_equal "`order`", @dialect.quote_id("order")
  end

  test "quote_id caches results" do
    result1 = @dialect.quote_id("users")
    result2 = @dialect.quote_id("users")

    assert_same result1, result2
  end

  test "qualified_name produces backtick-quoted table.column reference" do
    assert_equal "`users`.`name`", @dialect.qualified_name("users", "name")
  end

  test "supports_returning? returns false" do
    refute_predicate @dialect, :supports_returning?
  end

  test "name returns :mysql" do
    assert_equal :mysql, @dialect.name
  end

  test "supports_ddl_transactions? returns false" do
    refute_predicate @dialect, :supports_ddl_transactions?
  end

  test "supports_advisory_lock? returns true" do
    assert_predicate @dialect, :supports_advisory_lock?
  end

  test "advisory_lock_sql uses GET_LOCK" do
    assert_includes @dialect.advisory_lock_sql, "GET_LOCK"
    assert_includes @dialect.advisory_unlock_sql, "RELEASE_LOCK"
  end

  test "encode_boolean produces 1/0" do
    assert_equal 1, @dialect.encode_boolean(true)
    assert_equal 0, @dialect.encode_boolean(false)
  end

  test "cast_boolean interprets 1/0 string format" do
    assert @dialect.cast_boolean("1")
    refute @dialect.cast_boolean("0")
  end

  test "cast_integer delegates to base" do
    assert_equal 42, @dialect.cast_integer("42")
  end

  test "cast_decimal delegates to base" do
    assert_equal BigDecimal("3.14"), @dialect.cast_decimal("3.14")
  end

  test "array types raise unsupported error" do
    assert_raises(HakumiORM::Error) { @dialect.cast_int_array("{1,2}") }
    assert_raises(HakumiORM::Error) { @dialect.encode_int_array([1, 2]) }
    assert_raises(HakumiORM::Error) { @dialect.cast_str_array("{a,b}") }
    assert_raises(HakumiORM::Error) { @dialect.encode_str_array(%w[a b]) }
    assert_raises(HakumiORM::Error) { @dialect.cast_float_array("{1.0}") }
    assert_raises(HakumiORM::Error) { @dialect.encode_float_array([1.0]) }
    assert_raises(HakumiORM::Error) { @dialect.cast_bool_array("{t}") }
    assert_raises(HakumiORM::Error) { @dialect.encode_bool_array([true]) }
  end
end
