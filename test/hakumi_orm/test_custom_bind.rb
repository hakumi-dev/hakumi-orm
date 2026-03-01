# typed: false
# frozen_string_literal: true

require "test_helper"
require "bigdecimal"

Money = Struct.new(:cents) do
  def to_d
    BigDecimal(cents, 10) / 100
  end

  def self.from_decimal(raw)
    new((BigDecimal(raw) * 100).to_i)
  end
end

class MoneyField < HakumiORM::Field
  extend T::Sig

  ValueType = type_member { { fixed: Money } }

  sig { override.params(value: Money).returns(::HakumiORM::Bind) }
  def to_bind(value)
    ::HakumiORM::DecimalBind.new(value.to_d)
  end
end

class TestCustomTypeEndToEnd < HakumiORM::TestCase
  def teardown
    HakumiORM::Codegen::TypeRegistry.reset!
    super
  end

  test "MoneyField produces a DecimalBind with correct value" do
    field = MoneyField.new(:price, "t", "price", '"t"."price"')
    bind = field.to_bind(Money.new(9995))

    assert_instance_of HakumiORM::DecimalBind, bind
    assert_equal "99.95", bind.serialize
  end

  test "MoneyField eq compiles to parameterized SQL" do
    field = MoneyField.new(:price, "t", "price", '"t"."price"')
    expr = field.eq(Money.new(9995))
    dialect = HakumiORM::Dialect::Postgresql.new
    compiled = dialect.compiler.count(table: "t", where_expr: expr)

    assert_includes compiled.sql, '"t"."price" = $1'
    assert_equal 1, compiled.binds.length
    assert_equal "99.95", compiled.binds[0].serialize
  end

  test "MoneyField is_null works" do
    field = MoneyField.new(:price, "t", "price", '"t"."price"')
    expr = field.is_null
    dialect = HakumiORM::Dialect::Postgresql.new
    compiled = dialect.compiler.count(table: "t", where_expr: expr)

    assert_includes compiled.sql, '"t"."price" IS NULL'
  end

  test "TypeRegistry stores custom type metadata for codegen" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.from_decimal(_hv))" : "Money.from_decimal(#{raw_expr})"
      },
      field_class: "::MoneyField",
      bind_class: "::HakumiORM::DecimalBind"
    )

    entry = HakumiORM::Codegen::TypeRegistry.fetch(:money)

    assert_equal "Money", entry.ruby_type
    assert_equal "::MoneyField", entry.field_class
    assert_equal "::HakumiORM::DecimalBind", entry.bind_class
  end

  test "cast_expression generates correct hydration code" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :money,
      ruby_type: "Money",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.from_decimal(_hv))" : "Money.from_decimal(#{raw_expr})"
      },
      field_class: "::MoneyField",
      bind_class: "::HakumiORM::DecimalBind"
    )

    entry = HakumiORM::Codegen::TypeRegistry.fetch(:money)

    assert_equal "Money.from_decimal(raw)", entry.cast_expression.call("raw", false)
    assert_equal "((_hv = raw).nil? ? nil : Money.from_decimal(_hv))", entry.cast_expression.call("raw", true)
  end

  test "Money round-trip: Ruby -> Bind -> serialize -> Cast -> Ruby" do
    original = Money.new(9995)
    bind = HakumiORM::DecimalBind.new(original.to_d)
    pg_wire = bind.serialize
    restored = Money.from_decimal(pg_wire)

    assert_equal original.cents, restored.cents
  end
end
