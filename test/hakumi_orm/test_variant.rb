# typed: false
# frozen_string_literal: true

require "test_helper"

class TestVariant < HakumiORM::TestCase
  def setup
    @record = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: 25, active: true)
    @record_nil_age = UserRecord.new(id: 2, name: "Bob", email: "bob@test.com", age: nil, active: false)
  end

  test "VariantBase delegates all columns to wrapped record" do
    variant = UserRecord::VariantBase.new(record: @record)

    assert_equal 1, variant.id
    assert_equal "Alice", variant.name
    assert_equal "alice@test.com", variant.email
    assert_equal 25, variant.age
    assert variant.active
  end

  test "VariantBase preserves nilable types" do
    variant = UserRecord::VariantBase.new(record: @record_nil_age)

    assert_nil variant.age
  end

  test "VariantBase exposes record via protected accessor" do
    variant = UserRecord::VariantBase.new(record: @record)

    assert_raises(NoMethodError) { variant.record }
    assert_equal @record, variant.send(:record)
  end

  test "variant narrows nullable column to non-nilable via kwargs" do
    age = @record.age

    assert age, "precondition: @record.age must be non-nil for this test"

    variant = UserRecord::WithAge.new(record: @record, age: age)

    assert_equal 25, variant.age
    assert_instance_of Integer, variant.age
  end

  test "variant still delegates non-narrowed columns" do
    age = @record.age

    assert age, "precondition"

    variant = UserRecord::WithAge.new(record: @record, age: age)

    assert_equal 1, variant.id
    assert_equal "Alice", variant.name
    assert_equal "alice@test.com", variant.email
    assert variant.active
  end

  test "variant inherits from VariantBase" do
    assert_operator UserRecord::WithAge, :<, UserRecord::VariantBase
  end

  test "flow typing: constructs variant when field is present" do
    age = @record.age
    result = UserRecord::WithAge.new(record: @record, age: age) if age

    assert_instance_of UserRecord::WithAge, result
    assert_equal 25, result.age
  end

  test "flow typing: returns nil when field is absent" do
    nil_age = @record_nil_age.age
    nil_result = UserRecord::WithAge.new(record: @record_nil_age, age: nil_age) if nil_age

    assert_nil nil_result
  end
end
