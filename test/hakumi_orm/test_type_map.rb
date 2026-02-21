# typed: false
# frozen_string_literal: true

require "test_helper"

class TestTypeMap < HakumiORM::TestCase
  HT = HakumiORM::Codegen::HakumiType
  TM = HakumiORM::Codegen::TypeMap

  test "PG integer types resolve to HakumiType::Integer" do
    %w[integer bigint smallint serial bigserial int4 int8].each do |pg_type|
      assert_equal HT::Integer, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to Integer"
    end
  end

  test "PG string types resolve to HakumiType::String" do
    ["character varying", "text", "varchar", "uuid", "json", "jsonb", "bytea", "inet"].each do |pg_type|
      assert_equal HT::String, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to String"
    end
  end

  test "PG boolean resolves to HakumiType::Boolean" do
    assert_equal HT::Boolean, TM.hakumi_type(:postgresql, "boolean")
  end

  test "PG timestamp types resolve to HakumiType::Timestamp" do
    ["timestamp without time zone", "timestamp with time zone", "timestamptz"].each do |pg_type|
      assert_equal HT::Timestamp, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to Timestamp"
    end
  end

  test "PG numeric types resolve to HakumiType::Decimal" do
    %w[numeric decimal money].each do |pg_type|
      assert_equal HT::Decimal, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to Decimal"
    end
  end

  test "unknown PG type falls back to HakumiType::String" do
    assert_equal HT::String, TM.hakumi_type(:postgresql, "my_custom_type")
  end

  test "raises on unknown dialect" do
    assert_raises(ArgumentError) { TM.hakumi_type(:oracle, "varchar2") }
  end

  test "ruby_type_string wraps in T.nilable when nullable" do
    assert_equal "T.nilable(Integer)", HT::Integer.ruby_type_string(nullable: true)
    assert_equal "Integer", HT::Integer.ruby_type_string(nullable: false)
  end

  test "field_class returns fully qualified class for each type" do
    assert_equal "::HakumiORM::IntField", HT::Integer.field_class
    assert_equal "::HakumiORM::StrField", HT::String.field_class
    assert_equal "::HakumiORM::BoolField", HT::Boolean.field_class
    assert_equal "::HakumiORM::TimeField", HT::Timestamp.field_class
    assert_equal "::HakumiORM::DateField", HT::Date.field_class
    assert_equal "::HakumiORM::FloatField", HT::Float.field_class
    assert_equal "::HakumiORM::DecimalField", HT::Decimal.field_class
  end

  test "comparable? is true for numeric and temporal types" do
    [HT::Integer, HT::Float, HT::Decimal, HT::Timestamp, HT::Date].each do |ht|
      assert_predicate ht, :comparable?, "Expected #{ht.serialize} to be comparable"
    end

    [HT::String, HT::Boolean].each do |ht|
      refute_predicate ht, :comparable?, "Expected #{ht.serialize} to not be comparable"
    end
  end

  test "text? is true only for String" do
    assert_predicate HT::String, :text?
    refute_predicate HT::Integer, :text?
    refute_predicate HT::Boolean, :text?
  end

  test "cast_expression for nullable integer uses safe navigation" do
    assert_equal "raw&.to_i", TM.cast_expression(HT::Integer, "raw", nullable: true)
  end

  test "cast_expression for non-nullable integer calls to_i directly" do
    assert_equal "raw.to_i", TM.cast_expression(HT::Integer, "raw", nullable: false)
  end

  test "cast_expression for boolean handles PG t/f format" do
    nullable = TM.cast_expression(HT::Boolean, "raw", nullable: true)
    non_null = TM.cast_expression(HT::Boolean, "raw", nullable: false)

    assert_includes nullable, '== "t"'
    assert_includes non_null, '== "t"'
  end
end
