# typed: false
# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

class TestDialectRoundtripMatrix < HakumiORM::TestCase
  DialectCase = Struct.new(:name, :dialect, :supports_arrays, :time_keeps_usec, keyword_init: true)

  def setup
    @dialects = [
      DialectCase.new(
        name: :postgresql,
        dialect: HakumiORM::Dialect::Postgresql.new,
        supports_arrays: true,
        time_keeps_usec: true
      ),
      DialectCase.new(
        name: :mysql,
        dialect: HakumiORM::Dialect::Mysql.new,
        supports_arrays: false,
        time_keeps_usec: true
      ),
      DialectCase.new(
        name: :sqlite,
        dialect: HakumiORM::Dialect::Sqlite.new,
        supports_arrays: false,
        time_keeps_usec: false
      )
    ]
  end

  test "boolean roundtrip matrix" do
    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect

      assert(dialect.cast_boolean(dialect.encode_boolean(true)))
      refute(dialect.cast_boolean(dialect.encode_boolean(false)))
    end
  end

  test "integer and bigint-style roundtrip matrix" do
    values = [42, -5, 9_223_372_036_854_775_000]

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect

      values.each do |value|
        encoded = dialect.encode_integer(value)

        assert_equal value, dialect.cast_integer(encoded)
      end
    end
  end

  test "decimal roundtrip matrix preserves value" do
    values = [BigDecimal("99.99"), BigDecimal("123456789.123456")]

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect

      values.each do |value|
        encoded = dialect.encode_decimal(value)
        decoded = dialect.cast_decimal(encoded)

        assert_instance_of BigDecimal, decoded
        assert_equal value, decoded
      end
    end
  end

  test "date roundtrip matrix" do
    date = Date.new(2026, 2, 26)

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect
      encoded = dialect.encode_date(date)
      decoded = dialect.cast_date(encoded)

      assert_equal date, decoded
    end
  end

  test "time roundtrip matrix remains UTC and preserves expected precision" do
    time = Time.utc(2026, 2, 26, 12, 34, 56, 123_456)

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect
      encoded = dialect.encode_time(time)
      decoded = dialect.cast_time(encoded)

      assert_predicate decoded, :utc?
      assert_equal [2026, 2, 26, 12, 34, 56], [decoded.year, decoded.month, decoded.day, decoded.hour, decoded.min, decoded.sec]
      expected_usec = dialect_case.time_keeps_usec ? 123_456 : 0

      assert_equal expected_usec, decoded.usec
    end
  end

  test "time cast accepts explicit UTC offset" do
    @dialects.each do |dialect_case|
      decoded = dialect_case.dialect.cast_time("2026-02-26 12:34:56.123456+00:00")

      assert_predicate decoded, :utc?
      assert_equal 123_456, decoded.usec
    end
  end

  test "json roundtrip matrix uses HakumiORM::Json wrapper" do
    json = HakumiORM::Json.from_hash({ "name" => "Hakumi", "count" => 3, "active" => true })

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect
      encoded = dialect.encode_json(json)
      decoded = dialect.cast_json(encoded)

      assert_instance_of HakumiORM::Json, decoded
      assert_equal "Hakumi", decoded["name"]&.as_s
      assert_equal 3, decoded["count"]&.as_i
      assert(decoded["active"]&.as_bool)
    end
  end

  test "uuid uses string contract roundtrip across dialects" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"

    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect
      encoded = dialect.encode_string(uuid)
      decoded = dialect.cast_string(encoded)

      assert_equal uuid, decoded
    end
  end

  test "array type support matrix is explicit" do
    @dialects.each do |dialect_case|
      dialect = dialect_case.dialect

      if dialect_case.supports_arrays
        assert_equal [1, nil, 3], dialect.cast_int_array(dialect.encode_int_array([1, nil, 3]))
        assert_equal ["a", nil, "b"], dialect.cast_str_array(dialect.encode_str_array(["a", nil, "b"]))
        assert_equal [1.5, nil, 2.5], dialect.cast_float_array(dialect.encode_float_array([1.5, nil, 2.5]))
        assert_equal [true, false, nil], dialect.cast_bool_array(dialect.encode_bool_array([true, false, nil]))
      else
        assert_raises(HakumiORM::Error) { dialect.encode_int_array([1, 2]) }
        assert_raises(HakumiORM::Error) { dialect.encode_str_array(["a"]) }
        assert_raises(HakumiORM::Error) { dialect.cast_int_array("{1,2}") }
        assert_raises(HakumiORM::Error) { dialect.cast_str_array("{a,b}") }
      end
    end
  end
end
