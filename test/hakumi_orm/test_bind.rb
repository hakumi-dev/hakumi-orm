# typed: false
# frozen_string_literal: true

require "test_helper"

class TestBind < HakumiORM::TestCase
  test "DecimalBind serializes BigDecimal as fixed-point string" do
    bind = HakumiORM::DecimalBind.new(BigDecimal("99999.00001"))

    assert_instance_of String, bind.serialize
    assert_equal "99999.00001", bind.serialize
  end

  test "BoolBind converts true/false to t/f" do
    assert_equal "t", HakumiORM::BoolBind.new(true).serialize
    assert_equal "f", HakumiORM::BoolBind.new(false).serialize
  end

  test "TimeBind formats to UTC with microsecond precision" do
    t = Time.new(2024, 1, 15, 12, 30, 0, "+03:00")
    bind = HakumiORM::TimeBind.new(t)

    assert_equal "2024-01-15 09:30:00.000000", bind.serialize
  end

  test "DateBind formats as ISO 8601 string" do
    bind = HakumiORM::DateBind.new(Date.new(2024, 1, 15))

    assert_equal "2024-01-15", bind.serialize
  end

  test "NullBind returns nil" do
    assert_nil HakumiORM::NullBind.new.serialize
  end

  test "IntBind and FloatBind pass through numeric values unchanged" do
    assert_equal 42, HakumiORM::IntBind.new(42).serialize
    assert_in_delta 3.14, HakumiORM::FloatBind.new(3.14).serialize
  end

  test "StrBind passes through string value unchanged" do
    assert_equal "hello", HakumiORM::StrBind.new("hello").serialize
  end

  test "JsonBind serializes Json to JSON string" do
    json = HakumiORM::Json.from_hash({ "key" => "value" })
    bind = HakumiORM::JsonBind.new(json)

    assert_equal '{"key":"value"}', bind.serialize
  end
end
