# typed: false
# frozen_string_literal: true

require "test_helper"

class TestBindPortability < HakumiORM::TestCase
  test "BoolBind pg_value returns PostgreSQL-specific t/f" do
    assert_equal "t", HakumiORM::BoolBind.new(true).pg_value
    assert_equal "f", HakumiORM::BoolBind.new(false).pg_value
  end

  test "Cast.to_boolean recognizes PostgreSQL t but not MySQL/SQLite 1" do
    assert HakumiORM::Cast.to_boolean("t")
    refute HakumiORM::Cast.to_boolean("f")
    refute HakumiORM::Cast.to_boolean("1"), "MySQL/SQLite send 1 for true"
    refute HakumiORM::Cast.to_boolean("true"), "SQLite may send true literal"
  end

  test "TimeBind pg_value formats as UTC string" do
    t = Time.utc(2025, 1, 15, 9, 30, 0)
    result = HakumiORM::TimeBind.new(t).pg_value

    assert_kind_of String, result
    assert_includes result, "2025-01-15"
  end

  test "DecimalBind pg_value returns string representation" do
    d = BigDecimal("99999.00001")
    result = HakumiORM::DecimalBind.new(d).pg_value

    assert_equal "99999.00001", result
  end

  test "Dialect::Postgresql#encode_bind keeps t/f for booleans" do
    pg = HakumiORM::Dialect::Postgresql.new

    assert_equal "t", pg.encode_bind(HakumiORM::BoolBind.new(true))
    assert_equal "f", pg.encode_bind(HakumiORM::BoolBind.new(false))
  end

  test "Dialect::Mysql#encode_bind uses 1/0 for booleans" do
    mysql = HakumiORM::Dialect::Mysql.new

    assert_equal 1, mysql.encode_bind(HakumiORM::BoolBind.new(true))
    assert_equal 0, mysql.encode_bind(HakumiORM::BoolBind.new(false))
  end

  test "Dialect::Sqlite#encode_bind uses 1/0 for booleans" do
    sqlite = HakumiORM::Dialect::Sqlite.new

    assert_equal 1, sqlite.encode_bind(HakumiORM::BoolBind.new(true))
    assert_equal 0, sqlite.encode_bind(HakumiORM::BoolBind.new(false))
  end

  test "encode_binds delegates to encode_bind for each element" do
    mysql = HakumiORM::Dialect::Mysql.new
    binds = [HakumiORM::BoolBind.new(true), HakumiORM::IntBind.new(42), HakumiORM::StrBind.new("hello")]

    result = mysql.encode_binds(binds)

    assert_equal [1, 42, "hello"], result
  end

  test "CompiledQuery#params_for uses dialect encoding" do
    mysql = HakumiORM::Dialect::Mysql.new
    query = HakumiORM::CompiledQuery.new("SELECT 1", [HakumiORM::BoolBind.new(true)])

    assert_equal [1], query.params_for(mysql)
    assert_equal ["t"], query.pg_params
  end
end
