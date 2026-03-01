# typed: false
# frozen_string_literal: true

require "test_helper"

class TestCustomTypes < HakumiORM::TestCase
  def teardown
    HakumiORM::Codegen::TypeRegistry.reset!
    super
  end

  test "register a custom type" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.new(_hv))" : "Money.new(#{raw_expr})"
      },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    assert HakumiORM::Codegen::TypeRegistry.registered?(:money)
  end

  test "retrieve a registered custom type" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    entry = HakumiORM::Codegen::TypeRegistry.fetch(:money)

    assert_equal "Money", entry.ruby_type
    assert_equal "::MyApp::MoneyField", entry.field_class
    assert_equal "::MyApp::MoneyBind", entry.bind_class
  end

  test "duplicate registration raises" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    assert_raises(ArgumentError) do
      HakumiORM::Codegen::TypeRegistry.register(
        name: :money,
        ruby_type: "Money",
        cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
        field_class: "::MyApp::MoneyField",
        bind_class: "::MyApp::MoneyBind"
      )
    end
  end

  test "fetch unknown type raises" do
    assert_raises(KeyError) do
      HakumiORM::Codegen::TypeRegistry.fetch(:unknown)
    end
  end

  test "custom type can be mapped to a PG udt_name" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )
    HakumiORM::Codegen::TypeRegistry.map_pg_type("money_type", :money)

    entry = HakumiORM::Codegen::TypeRegistry.resolve_pg("money_type")

    assert_equal "Money", entry.ruby_type
  end

  test "resolve_pg returns nil for unknown pg type" do
    assert_nil HakumiORM::Codegen::TypeRegistry.resolve_pg("nonexistent")
  end

  test "custom type generates cast expression" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.new(_hv))" : "Money.new(#{raw_expr})"
      },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    entry = HakumiORM::Codegen::TypeRegistry.fetch(:money)
    expr = entry.cast_expression.call("raw", false)

    assert_equal "Money.new(raw)", expr
  end

  test "custom type generates nullable cast expression" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.new(_hv))" : "Money.new(#{raw_expr})"
      },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    entry = HakumiORM::Codegen::TypeRegistry.fetch(:money)
    expr = entry.cast_expression.call("raw", true)

    assert_equal "((_hv = raw).nil? ? nil : Money.new(_hv))", expr
  end

  test "reset clears all registrations" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )
    HakumiORM::Codegen::TypeRegistry.reset!

    refute HakumiORM::Codegen::TypeRegistry.registered?(:money)
  end

  # --- Registration window ---

  test "register inside configure block succeeds" do
    HakumiORM.configure do |_config|
      HakumiORM::Codegen::TypeRegistry.register(
        name: :money,
        ruby_type: "Money",
        cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
        field_class: "::MyApp::MoneyField",
        bind_class: "::MyApp::MoneyBind"
      )
    end

    assert HakumiORM::Codegen::TypeRegistry.registered?(:money)
  end

  test "register after configure block closes raises" do
    HakumiORM.configure { |_config| }

    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Codegen::TypeRegistry.register(
        name: :money,
        ruby_type: "Money",
        cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
        field_class: "::MyApp::MoneyField",
        bind_class: "::MyApp::MoneyBind"
      )
    end

    assert_includes err.message, "configure"
  end

  test "map_pg_type after configure block closes raises" do
    HakumiORM.configure { |_config| }

    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Codegen::TypeRegistry.map_pg_type("money_col", :money)
    end

    assert_includes err.message, "configure"
  end

  test "reset! re-opens the registration window" do
    HakumiORM.configure { |_config| }
    HakumiORM::Codegen::TypeRegistry.reset!

    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
      field_class: "::MyApp::MoneyField",
      bind_class: "::MyApp::MoneyBind"
    )

    assert HakumiORM::Codegen::TypeRegistry.registered?(:money)
  end

  test "re-entering configure re-opens the window" do
    HakumiORM.configure { |_config| }

    HakumiORM.configure do |_config|
      HakumiORM::Codegen::TypeRegistry.register(
        name: :money,
        ruby_type: "Money",
        cast_expression: ->(_raw_expr, _nullable) { "Money.new(raw)" },
        field_class: "::MyApp::MoneyField",
        bind_class: "::MyApp::MoneyBind"
      )
    end

    assert HakumiORM::Codegen::TypeRegistry.registered?(:money)
  end
end
