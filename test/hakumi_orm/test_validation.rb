# typed: false
# frozen_string_literal: true

require "test_helper"

class TestValidation < HakumiORM::TestCase
  HOOK_METHODS = %i[on_all on_create on_update on_persist].freeze

  def setup
    remove_contract_hooks!
    UserRecord::Contract.clear_validations!
  end

  def teardown
    remove_contract_hooks!
    UserRecord::Contract.clear_validations!
  end

  test "Errors starts empty and valid" do
    e = HakumiORM::Errors.new

    assert_predicate e, :valid?
    assert_equal 0, e.count
    assert_empty e.messages
  end

  test "Errors#add stores messages grouped by field" do
    e = HakumiORM::Errors.new
    e.add(:name, "cannot be blank")
    e.add(:name, "is too short")
    e.add(:email, "is invalid")

    refute_predicate e, :valid?
    assert_equal 3, e.count
    assert_equal({ name: ["cannot be blank", "is too short"], email: ["is invalid"] }, e.messages)
  end

  test "Errors#full_messages joins field and message" do
    e = HakumiORM::Errors.new
    e.add(:name, "cannot be blank")
    e.add(:email, "is invalid")

    assert_equal ["name cannot be blank", "email is invalid"], e.full_messages
  end

  test "Errors tracks details and supports [] lookup" do
    e = HakumiORM::Errors.new
    e.add(:name, "cannot be blank", type: :blank)
    e.add(:name, "is too short", type: :too_short)

    assert_equal ["cannot be blank", "is too short"], e[:name]
    assert_equal [{ error: "blank" }, { error: "too_short" }], e.details[:name]
  end

  test "Errors#clear empties messages and details" do
    e = HakumiORM::Errors.new
    e.add(:base, "cannot proceed", type: :invalid)

    refute_predicate e, :empty?
    assert_predicate e, :invalid?

    e.clear

    assert_predicate e, :empty?
    assert_predicate e, :valid?
    assert_empty e.messages
    assert_empty e.details
  end

  test "Errors#full_messages keeps base messages unprefixed" do
    e = HakumiORM::Errors.new
    e.add(:base, "cannot be deleted")

    assert_equal ["cannot be deleted"], e.full_messages
  end

  test "ValidationError wraps Errors and produces a readable message" do
    e = HakumiORM::Errors.new
    e.add(:name, "cannot be blank")

    err = HakumiORM::ValidationError.new(e)

    assert_kind_of HakumiORM::Error, err
    assert_equal e, err.errors
    assert_includes err.message, "name cannot be blank"
  end

  test "New#validate! returns Validated when contract passes" do
    record = UserRecord.build(name: "Alice", email: "alice@example.com", active: true)

    validated = record.validate!

    assert_instance_of UserRecord::Validated, validated
    assert_equal "Alice", validated.name
    assert_equal "alice@example.com", validated.email
    assert validated.active
    assert_nil validated.age
  end

  test "New#validate! freezes the underlying New record" do
    record = UserRecord.build(name: "Alice", email: "alice@example.com", active: true)
    record.validate!

    assert_predicate record, :frozen?
  end

  test "Validated delegates all fields to frozen New" do
    record = UserRecord.build(name: "Bob", email: "bob@test.com", active: false, age: 30)
    validated = record.validate!

    assert_equal "Bob", validated.name
    assert_equal "bob@test.com", validated.email
    refute validated.active
    assert_equal 30, validated.age
  end

  test "New and Validated both satisfy Checkable" do
    record = UserRecord.build(name: "Alice", email: "alice@example.com", active: true)
    validated = record.validate!

    assert_kind_of UserRecord::Checkable, record
    assert_kind_of UserRecord::Checkable, validated
  end

  test "validate! raises ValidationError when on_create fails" do
    UserRecord::Contract.define_singleton_method(:on_create) do |record, e|
      e.add(:name, "cannot be blank") if record.name.strip.empty?
    end

    record = UserRecord.build(name: "", email: "x@y.com", active: true)

    err = assert_raises(HakumiORM::ValidationError) { record.validate! }
    assert_includes err.errors.messages[:name], "cannot be blank"
  end

  test "validate! raises ValidationError when on_all fails" do
    UserRecord::Contract.define_singleton_method(:on_all) do |record, e|
      e.add(:email, "must contain @") unless record.email.include?("@")
    end

    record = UserRecord.build(name: "Alice", email: "invalid", active: true)

    err = assert_raises(HakumiORM::ValidationError) { record.validate! }
    assert_includes err.errors.messages[:email], "must contain @"
  end

  test "validate! collects errors from both on_all and on_create" do
    UserRecord::Contract.define_singleton_method(:on_all) do |record, e|
      e.add(:email, "is invalid") unless record.email.include?("@")
    end
    UserRecord::Contract.define_singleton_method(:on_create) do |record, e|
      e.add(:name, "too short") if record.name.length < 2
    end

    record = UserRecord.build(name: "A", email: "bad", active: true)

    err = assert_raises(HakumiORM::ValidationError) { record.validate! }
    assert_includes err.errors.messages[:email], "is invalid"
    assert_includes err.errors.messages[:name], "too short"
    assert_equal 2, err.errors.count
  end

  test "validates presence adds error on create flow" do
    UserRecord::Contract.validates(:name, presence: true, on: :create)
    record = UserRecord.build(name: "  ", email: "x@y.com", active: true)

    err = assert_raises(HakumiORM::ValidationError) { record.validate! }
    assert_equal ["can't be blank"], err.errors[:name]
    assert_equal [{ error: "blank" }], err.errors.details[:name]
  end

  test "validates blank requires empty value" do
    UserRecord::Contract.validates(:name, blank: true)
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "Alice", email: "a@b.com", active: true)

    UserRecord::Contract.on_all(record, errors)

    assert_equal ["must be blank"], errors[:name]
  end

  test "validates length format numericality inclusion apply together" do
    UserRecord::Contract.validates(:name, length: { minimum: 3, maximum: 5 })
    UserRecord::Contract.validates(:email, format: { with: /\A[^@\s]+@[^@\s]+\z/ })
    UserRecord::Contract.validates(:age, numericality: { only_integer: true, greater_than_or_equal_to: 18 })
    UserRecord::Contract.validates(:active, inclusion: { in: [true] })
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "Al", email: "broken", age: 17, active: false)

    UserRecord::Contract.on_all(record, errors)

    assert_includes errors[:name], "is too short (minimum is 3)"
    assert_equal ["is invalid"], errors[:email]
    assert_includes errors[:age], "must be greater than or equal to 18.0"
    assert_equal ["is not included in the list"], errors[:active]
  end

  test "validates allow_nil and allow_blank skip checks" do
    UserRecord::Contract.validates(:age, numericality: { only_integer: true }, allow_nil: true)
    UserRecord::Contract.validates(:name, format: { with: /\A[a-z]+\z/ }, allow_blank: true)
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "   ", email: "x@y.com", age: nil, active: true)

    UserRecord::Contract.on_all(record, errors)

    assert_predicate errors, :empty?
  end

  test "validates custom message overrides default" do
    UserRecord::Contract.validates(:name, presence: true, message: "required")
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "", email: "x@y.com", active: true)

    UserRecord::Contract.on_all(record, errors)

    assert_equal ["required"], errors[:name]
  end

  test "validates supports proc message, dynamic inclusion and if/unless conditions" do
    UserRecord::Contract.validates(:active, inclusion: { in: ->(_record) { [true] } }, message: ->(_record) { "must stay enabled" })
    UserRecord::Contract.validates(:name, presence: true, if: ->(record) { record.active == false })
    UserRecord::Contract.validates(:email, format: { with: /\A[a-z]+@example\.com\z/ }, unless: :active)
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "", email: "bad@mail.com", active: false)

    UserRecord::Contract.on_all(record, errors)

    assert_equal ["must stay enabled"], errors[:active]
    assert_equal ["can't be blank"], errors[:name]
    assert_equal ["is invalid"], errors[:email]
  end

  test "validates exclusion blocks reserved values" do
    UserRecord::Contract.validates(:email, exclusion: { in: ["root@example.com"] })
    errors = HakumiORM::Errors.new
    record = UserRecord::New.new(name: "Alice", email: "root@example.com", active: true)

    UserRecord::Contract.on_all(record, errors)

    assert_equal ["is reserved"], errors[:email]
  end

  test "validates comparison supports numeric checks and symbol/proc operands" do
    UserRecord::Contract.validates(:age, comparison: { greater_than: 17 }, on: :destroy)
    UserRecord::Contract.validates(:age, comparison: { less_than_or_equal_to: :id }, on: :destroy)
    UserRecord::Contract.validates(:age, comparison: { other_than: ->(_record) { 25 } }, on: :destroy)
    errors = HakumiORM::Errors.new
    record = UserRecord.new(id: 20, name: "Alice", email: "x@y.com", age: 25, active: true)

    UserRecord::Contract.on_destroy(record, errors)

    assert_includes errors[:age], "must be less than or equal to 20"
    assert_includes errors[:age], "must be other than 25"
  end

  private

  def remove_contract_hooks!
    sc = UserRecord::Contract.singleton_class
    HOOK_METHODS.each { |m| sc.remove_method(m) if sc.method_defined?(m, false) }
  end
end
