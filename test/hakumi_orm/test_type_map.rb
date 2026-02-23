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
    ["character varying", "text", "varchar", "bytea", "inet"].each do |pg_type|
      assert_equal HT::String, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to String"
    end
  end

  test "PG json types resolve to HakumiType::Json" do
    %w[json jsonb].each do |pg_type|
      assert_equal HT::Json, TM.hakumi_type(:postgresql, pg_type),
                   "Expected #{pg_type} to map to Json"
    end
  end

  test "PG uuid resolves to HakumiType::Uuid" do
    assert_equal HT::Uuid, TM.hakumi_type(:postgresql, "uuid")
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

  test "MySQL integer types resolve correctly" do
    %w[int bigint smallint mediumint tinyint].each do |t|
      assert_equal HT::Integer, TM.hakumi_type(:mysql, t),
                   "Expected #{t} to map to Integer"
    end
  end

  test "MySQL string types resolve correctly" do
    %w[varchar char text mediumtext longtext tinytext].each do |t|
      assert_equal HT::String, TM.hakumi_type(:mysql, t),
                   "Expected #{t} to map to String"
    end
  end

  test "MySQL tinyint(1) resolves to Boolean" do
    assert_equal HT::Boolean, TM.hakumi_type(:mysql, "tinyint(1)")
  end

  test "MySQL json resolves to Json" do
    assert_equal HT::Json, TM.hakumi_type(:mysql, "json")
  end

  test "MySQL datetime/timestamp resolve to Timestamp" do
    %w[datetime timestamp].each do |t|
      assert_equal HT::Timestamp, TM.hakumi_type(:mysql, t),
                   "Expected #{t} to map to Timestamp"
    end
  end

  test "MySQL decimal resolves to Decimal" do
    assert_equal HT::Decimal, TM.hakumi_type(:mysql, "decimal")
  end

  test "MySQL float/double resolve to Float" do
    %w[float double].each do |t|
      assert_equal HT::Float, TM.hakumi_type(:mysql, t),
                   "Expected #{t} to map to Float"
    end
  end

  test "SQLite INTEGER resolves to Integer" do
    assert_equal HT::Integer, TM.hakumi_type(:sqlite, "INTEGER")
  end

  test "SQLite TEXT resolves to String" do
    assert_equal HT::String, TM.hakumi_type(:sqlite, "TEXT")
  end

  test "SQLite REAL resolves to Float" do
    assert_equal HT::Float, TM.hakumi_type(:sqlite, "REAL")
  end

  test "SQLite BOOLEAN resolves to Boolean" do
    assert_equal HT::Boolean, TM.hakumi_type(:sqlite, "BOOLEAN")
  end

  test "SQLite NUMERIC resolves to Decimal" do
    assert_equal HT::Decimal, TM.hakumi_type(:sqlite, "NUMERIC")
  end

  test "SQLite DATE resolves to Date" do
    assert_equal HT::Date, TM.hakumi_type(:sqlite, "DATE")
  end

  test "SQLite DATETIME resolves to Timestamp" do
    assert_equal HT::Timestamp, TM.hakumi_type(:sqlite, "DATETIME")
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
    assert_equal "::HakumiORM::JsonField", HT::Json.field_class
    assert_equal "::HakumiORM::StrField", HT::Uuid.field_class
  end

  test "comparable? is true for numeric and temporal types" do
    [HT::Integer, HT::Float, HT::Decimal, HT::Timestamp, HT::Date].each do |ht|
      assert_predicate ht, :comparable?, "Expected #{ht.serialize} to be comparable"
    end

    [HT::String, HT::Boolean, HT::Json, HT::Uuid].each do |ht|
      refute_predicate ht, :comparable?, "Expected #{ht.serialize} to not be comparable"
    end
  end

  test "text? is true for String and Uuid" do
    assert_predicate HT::String, :text?
    assert_predicate HT::Uuid, :text?
    refute_predicate HT::Integer, :text?
    refute_predicate HT::Boolean, :text?
    refute_predicate HT::Json, :text?
  end

  test "cast_expression for nullable integer delegates to dialect" do
    assert_equal "((_hv = raw).nil? ? nil : dialect.cast_integer(_hv))",
                 TM.cast_expression(HT::Integer, "raw", nullable: true)
  end

  test "cast_expression for non-nullable integer delegates to dialect" do
    assert_equal "dialect.cast_integer(raw)",
                 TM.cast_expression(HT::Integer, "raw", nullable: false)
  end

  test "cast_expression for boolean delegates to dialect" do
    nullable = TM.cast_expression(HT::Boolean, "raw", nullable: true)
    non_null = TM.cast_expression(HT::Boolean, "raw", nullable: false)

    assert_includes nullable, "dialect.cast_boolean"
    assert_includes non_null, "dialect.cast_boolean"
  end

  test "cast_expression for json delegates to dialect" do
    non_null = TM.cast_expression(HT::Json, "raw", nullable: false)

    assert_equal "dialect.cast_json(raw)", non_null
  end

  test "cast_expression for nullable json wraps with nil check" do
    nullable = TM.cast_expression(HT::Json, "raw", nullable: true)

    assert_includes nullable, "dialect.cast_json"
    assert_includes nullable, "nil"
  end

  test "cast_expression for uuid is identity (String)" do
    assert_equal "raw", TM.cast_expression(HT::Uuid, "raw", nullable: false)
  end

  test "ruby_type returns correct types for Json and Uuid" do
    assert_equal "::HakumiORM::Json", HT::Json.ruby_type
    assert_equal "String", HT::Uuid.ruby_type
  end

  test "bind_class returns correct classes for Json and Uuid" do
    assert_equal "::HakumiORM::JsonBind", HT::Json.bind_class
    assert_equal "::HakumiORM::StrBind", HT::Uuid.bind_class
  end
end
