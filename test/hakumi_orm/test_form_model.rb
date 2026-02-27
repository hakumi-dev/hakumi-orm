# typed: false
# frozen_string_literal: true

require "test_helper"

module FormModelTestHelpers
  module Adapter
    extend HakumiORM::FormModelAdapter
    include HakumiORM::FormModel::Host

    def self.apply_to(base)
      base.prepend(self) unless base < self
    end

    def to_model
      :adapted
    end
  end
end

class DefaultFormModelDummy
  include HakumiORM::FormModel::Default

  attr_reader :id

  def initialize(id: nil, invalid: false)
    @id = id
    @invalid = invalid
  end

  private

  def run_form_model_validation(errors)
    errors.add(:name, "cannot be blank", type: :blank) if @invalid
  end
end

class TestFormModel < HakumiORM::TestCase
  test "configuration uses a non-nil default form adapter" do
    assert_equal HakumiORM::FormModel::NoopAdapter, HakumiORM.config.form_model_adapter
  end

  def setup
    @previous_adapter = HakumiORM.config.form_model_adapter
    HakumiORM.config.form_model_adapter = HakumiORM::FormModel::NoopAdapter
  end

  def teardown
    HakumiORM.config.form_model_adapter = @previous_adapter
  end

  test "default form model exposes Rails-friendly basics" do
    rec = DefaultFormModelDummy.new(id: 42)

    assert_predicate rec, :persisted?
    assert_equal [42], rec.to_key
    assert_equal "42", rec.to_param
    assert_equal rec, rec.to_model
    assert_respond_to DefaultFormModelDummy, :model_name
    assert_equal "default_form_model_dummy", DefaultFormModelDummy.model_name.param_key
    assert_equal "default_form_model_dummies", DefaultFormModelDummy.model_name.route_key
    form_class = Class.new do
      include HakumiORM::FormModel::Default
    end

    assert_equal "First name", form_class.human_attribute_name(:first_name)
  end

  test "default form model validation hook populates errors" do
    rec = DefaultFormModelDummy.new(invalid: true)

    refute_predicate rec, :valid?
    assert_predicate rec, :invalid?
    assert_equal ["cannot be blank"], rec.errors[:name]
  end

  test "form model can be overridden by configured adapter module" do
    HakumiORM.config.form_model_adapter = FormModelTestHelpers::Adapter

    klass = Class.new do
      include HakumiORM::FormModel::Default
    end

    assert_equal :adapted, klass.new.to_model
  end
end
