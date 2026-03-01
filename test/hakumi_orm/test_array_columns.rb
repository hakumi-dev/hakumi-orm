# typed: false
# frozen_string_literal: true

require "test_helper"

class TestArrayColumns < HakumiORM::TestCase
  test "Cast.to_int_array parses PG array literal" do
    assert_equal [1, 2, 3], HakumiORM::Cast.to_int_array("{1,2,3}")
  end

  test "Cast.to_int_array handles empty array" do
    assert_empty HakumiORM::Cast.to_int_array("{}")
  end

  test "Cast.to_int_array handles NULL elements" do
    assert_equal [1, nil, 3], HakumiORM::Cast.to_int_array("{1,NULL,3}")
  end

  test "Cast.to_str_array parses PG array literal" do
    assert_equal %w[a b c], HakumiORM::Cast.to_str_array("{a,b,c}")
  end

  test "Cast.to_str_array handles quoted strings with commas" do
    assert_equal ["hello, world", "foo"], HakumiORM::Cast.to_str_array('{"hello, world",foo}')
  end

  test "Cast.to_str_array handles empty array" do
    assert_empty HakumiORM::Cast.to_str_array("{}")
  end

  test "Cast.to_str_array handles NULL elements" do
    assert_equal ["a", nil, "c"], HakumiORM::Cast.to_str_array("{a,NULL,c}")
  end

  test "Cast.to_float_array parses PG array literal" do
    assert_equal [1.5, 2.7], HakumiORM::Cast.to_float_array("{1.5,2.7}")
  end

  test "IntArrayBind serializes to PG array literal" do
    bind = HakumiORM::IntArrayBind.new([1, 2, 3])

    assert_equal "{1,2,3}", bind.serialize
  end

  test "IntArrayBind handles empty array" do
    bind = HakumiORM::IntArrayBind.new([])

    assert_equal "{}", bind.serialize
  end

  test "StrArrayBind always quotes non-NULL values" do
    bind = HakumiORM::StrArrayBind.new(["hello, world", "foo"])

    assert_equal '{"hello, world","foo"}', bind.serialize
  end

  test "StrArrayBind handles empty array" do
    bind = HakumiORM::StrArrayBind.new([])

    assert_equal "{}", bind.serialize
  end

  test "StrArrayBind handles values with curly braces" do
    bind = HakumiORM::StrArrayBind.new(["{nested}", "normal"])

    assert_equal '{"{nested}","normal"}', bind.serialize
  end

  test "StrArrayBind handles values with newlines and tabs" do
    bind = HakumiORM::StrArrayBind.new(%W[line1\nline2 tab\there])

    assert_equal "{\"line1\nline2\",\"tab\there\"}", bind.serialize
  end

  test "StrArrayBind handles NULL elements" do
    bind = HakumiORM::StrArrayBind.new(["a", nil, "b"])

    assert_equal '{"a",NULL,"b"}', bind.serialize
  end

  test "StrArrayBind escapes all quotes and backslashes" do
    bind = HakumiORM::StrArrayBind.new(['a"b"c', 'x\\y\\z'])

    assert_equal '{"a\\"b\\"c","x\\\\y\\\\z"}', bind.serialize
  end

  test "StrArrayBind escaped values round-trip through Cast" do
    values = ['a"b"c', 'x\\y\\z', nil]
    encoded = HakumiORM::StrArrayBind.new(values).serialize

    assert_equal values, HakumiORM::Cast.to_str_array(encoded)
  end

  test "FloatArrayBind serializes to PG array literal" do
    bind = HakumiORM::FloatArrayBind.new([1.5, 2.7])

    assert_equal "{1.5,2.7}", bind.serialize
  end

  test "IntArrayField supports eq predicate" do
    field = HakumiORM::IntArrayField.new(:tags, "t", "tags", '"t"."tags"')
    expr = field.eq([1, 2])

    assert_instance_of HakumiORM::Predicate, expr
  end

  test "IntArrayField supports is_null" do
    field = HakumiORM::IntArrayField.new(:tags, "t", "tags", '"t"."tags"')
    expr = field.is_null

    assert_instance_of HakumiORM::Predicate, expr
  end

  test "StrArrayField supports eq predicate" do
    field = HakumiORM::StrArrayField.new(:names, "t", "names", '"t"."names"')
    expr = field.eq(%w[a b])

    assert_instance_of HakumiORM::Predicate, expr
  end

  test "IntegerArray maps to correct ruby type" do
    ht = HakumiORM::Codegen::HakumiType::IntegerArray

    assert_equal "T::Array[T.nilable(Integer)]", ht.ruby_type
  end

  test "StringArray maps to correct ruby type" do
    ht = HakumiORM::Codegen::HakumiType::StringArray

    assert_equal "T::Array[T.nilable(String)]", ht.ruby_type
  end

  test "FloatArray maps to correct ruby type" do
    ht = HakumiORM::Codegen::HakumiType::FloatArray

    assert_equal "T::Array[T.nilable(Float)]", ht.ruby_type
  end

  test "IntegerArray field_class is IntArrayField" do
    assert_equal "::HakumiORM::IntArrayField", HakumiORM::Codegen::HakumiType::IntegerArray.field_class
  end

  test "IntegerArray bind_class is IntArrayBind" do
    assert_equal "::HakumiORM::IntArrayBind", HakumiORM::Codegen::HakumiType::IntegerArray.bind_class
  end

  test "PG type map resolves _int4 to IntegerArray" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "ARRAY", "_int4")

    assert_equal HakumiORM::Codegen::HakumiType::IntegerArray, ht
  end

  test "PG type map resolves _text to StringArray" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "ARRAY", "_text")

    assert_equal HakumiORM::Codegen::HakumiType::StringArray, ht
  end

  test "PG type map resolves _float8 to FloatArray" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "ARRAY", "_float8")

    assert_equal HakumiORM::Codegen::HakumiType::FloatArray, ht
  end

  test "PG type map resolves _varchar to StringArray" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "ARRAY", "_varchar")

    assert_equal HakumiORM::Codegen::HakumiType::StringArray, ht
  end

  test "PG type map resolves _bool to BooleanArray" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "ARRAY", "_bool")

    assert_equal HakumiORM::Codegen::HakumiType::BooleanArray, ht
  end

  test "IntegerArray cast expression delegates to dialect" do
    expr = HakumiORM::Codegen::TypeMap.cast_expression(
      HakumiORM::Codegen::HakumiType::IntegerArray, "raw", nullable: false
    )

    assert_includes expr, "dialect.cast_int_array"
  end

  test "StringArray cast expression delegates to dialect" do
    expr = HakumiORM::Codegen::TypeMap.cast_expression(
      HakumiORM::Codegen::HakumiType::StringArray, "raw", nullable: false
    )

    assert_includes expr, "dialect.cast_str_array"
  end

  test "IntArrayField eq compiles to parameterized SQL" do
    dialect = HakumiORM::Dialect::Postgresql.new
    field = HakumiORM::IntArrayField.new(:tags, "t", "tags", '"t"."tags"')
    expr = field.eq([1, 2, 3])
    compiled = dialect.compiler.count(table: "t", where_expr: expr)

    assert_includes compiled.sql, '"t"."tags" = $1'
    assert_equal 1, compiled.binds.length
    assert_equal "{1,2,3}", compiled.binds[0].serialize
  end
end
