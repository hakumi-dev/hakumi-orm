# typed: false
# frozen_string_literal: true

require "test_helper"

# A minimal custom validator used throughout this file.
class UppercaseValidator
  include HakumiORM::Validation::Validators::Base

  def validate(context, rule)
    value = context.value
    return unless value.is_a?(String)
    return if value == value.upcase

    context.add_error(rule: rule, type: :not_uppercase, default_message: "must be uppercase")
  end
end

# A minimal record stub that satisfies ValidatableInterface.
class StubRecord
  include HakumiORM::Validation::ValidatableInterface

  def initialize(attrs)
    @attrs = attrs
  end

  def validation_attribute?(attribute)
    @attrs.key?(attribute)
  end

  def validation_value(attribute)
    @attrs[attribute]
  end
end

class TestValidatorRegistry < HakumiORM::TestCase
  Registry = HakumiORM::Validation::Validators::Registry

  test "register stores a custom validator" do
    Registry.register(:uppercase, UppercaseValidator.new)

    assert Registry.registered?(:uppercase)
  end

  test "fetch returns a registered validator" do
    v = UppercaseValidator.new
    Registry.register(:uppercase, v)

    assert_equal v, Registry.fetch(:uppercase)
  end

  test "fetch on unknown kind raises ArgumentError" do
    assert_raises(ArgumentError) { Registry.fetch(:nonexistent) }
  end

  test "duplicate registration raises ArgumentError" do
    Registry.register(:uppercase, UppercaseValidator.new)

    assert_raises(ArgumentError) { Registry.register(:uppercase, UppercaseValidator.new) }
  end

  test "registered? returns false for unknown kind" do
    refute Registry.registered?(:unknown_xyz)
  end

  test "registered? returns true for built-in validators" do
    assert Registry.registered?(:presence)
    assert Registry.registered?(:length)
    assert Registry.registered?(:format)
  end

  test "reset! removes custom validators" do
    Registry.register(:uppercase, UppercaseValidator.new)
    Registry.reset!

    refute Registry.registered?(:uppercase)
  end

  test "reset! preserves built-in validators" do
    Registry.register(:uppercase, UppercaseValidator.new)
    Registry.reset!

    assert Registry.registered?(:presence)
  end

  test "validates dispatches to a registered custom validator" do
    errors_captured = []

    spy = Class.new do
      include HakumiORM::Validation::Validators::Base

      define_method(:validate) do |context, _rule|
        errors_captured << context.value
      end
    end.new

    Registry.register(:spy_rule, spy)

    contract = Class.new do
      extend HakumiORM::Validation::ContractDSL
      validates :name, spy_rule: {}
    end

    errors = HakumiORM::Errors.new
    contract.run_validations_for_all(StubRecord.new(name: "hello"), errors)

    assert_equal ["hello"], errors_captured
  end

  test "custom validator receives options from the validates call" do
    received_rule = nil

    spy = Class.new do
      include HakumiORM::Validation::Validators::Base

      define_method(:validate) do |_context, rule|
        received_rule = rule
      end
    end.new

    Registry.register(:spy_rule, spy)

    contract = Class.new do
      extend HakumiORM::Validation::ContractDSL
      validates :name, spy_rule: { threshold: 5, message: "too short" }
    end

    errors = HakumiORM::Errors.new
    contract.run_validations_for_all(StubRecord.new(name: "hello"), errors)

    assert_equal 5, received_rule[:threshold]
    assert_equal "too short", received_rule[:message]
  end

  test "custom validator adds errors visible to caller" do
    Registry.register(:uppercase, UppercaseValidator.new)

    contract = Class.new do
      extend HakumiORM::Validation::ContractDSL
      validates :name, uppercase: {}
    end

    errors = HakumiORM::Errors.new
    contract.run_validations_for_all(StubRecord.new(name: "lowercase"), errors)

    assert_equal ["must be uppercase"], errors[:name]
  end

  test "custom validator passes when value satisfies rule" do
    Registry.register(:uppercase, UppercaseValidator.new)

    contract = Class.new do
      extend HakumiORM::Validation::ContractDSL
      validates :name, uppercase: {}
    end

    errors = HakumiORM::Errors.new
    contract.run_validations_for_all(StubRecord.new(name: "UPPERCASE"), errors)

    assert_predicate errors, :empty?
  end

  test "unknown kwargs not in registry are silently ignored" do
    contract = Class.new do
      extend HakumiORM::Validation::ContractDSL
      validates :name, presence: true, totally_unknown: {}
    end

    errors = HakumiORM::Errors.new
    contract.run_validations_for_all(StubRecord.new(name: "hello"), errors)

    assert_predicate errors, :empty?
  end
end
