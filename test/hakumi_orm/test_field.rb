# typed: false
# frozen_string_literal: true

require "test_helper"

class TestField < HakumiORM::TestCase
  test "each field type produces the correct Bind subclass" do
    assert_instance_of HakumiORM::IntBind, UserSchema::AGE.eq(1).binds[0]
    assert_instance_of HakumiORM::StrBind, UserSchema::NAME.eq("x").binds[0]
    assert_instance_of HakumiORM::BoolBind, UserSchema::ACTIVE.eq(true).binds[0]
  end

  test "predicate carries the field identity for SQL generation" do
    pred = UserSchema::AGE.gt(18)

    assert_equal '"users"."age"', pred.field.qualified_name
    assert_equal "users", pred.field.table_name
    assert_equal "age", pred.field.column_name
  end

  test "ComparableField exposes gt, gte, lt, lte, between" do
    int_field = UserSchema::AGE

    assert_respond_to int_field, :gt
    assert_respond_to int_field, :gte
    assert_respond_to int_field, :lt
    assert_respond_to int_field, :lte
    assert_respond_to int_field, :between
  end

  test "TextField exposes like and ilike but not gt" do
    str_field = UserSchema::NAME

    assert_respond_to str_field, :like
    assert_respond_to str_field, :ilike
    refute_respond_to str_field, :gt
    refute_respond_to str_field, :between
  end

  test "BoolField has neither comparison nor text operations" do
    bool_field = UserSchema::ACTIVE

    refute_respond_to bool_field, :gt
    refute_respond_to bool_field, :like
    refute_respond_to bool_field, :between
  end

  test "like always produces StrBind regardless of field type" do
    pred = UserSchema::EMAIL.like("%@gmail.com")

    assert_instance_of HakumiORM::StrBind, pred.binds[0]
    assert_equal "%@gmail.com", pred.binds[0].value
  end

  test "between produces exactly two binds in correct order" do
    pred = UserSchema::AGE.between(18, 65)

    assert_equal 2, pred.binds.length
    assert_equal 18, pred.binds[0].value
    assert_equal 65, pred.binds[1].value
  end

  test "in_list produces one bind per element" do
    pred = UserSchema::AGE.in_list([10, 20, 30])

    assert_equal :in, pred.op
    assert_equal 3, pred.binds.length
    assert_equal [10, 20, 30], pred.binds.map(&:value)
  end

  test "is_null and is_not_null produce zero binds" do
    assert_empty UserSchema::AGE.is_null.binds
    assert_empty UserSchema::AGE.is_not_null.binds
  end

  test "asc and desc produce OrderClause with correct direction" do
    assert_equal :asc, UserSchema::NAME.asc.direction
    assert_equal :desc, UserSchema::NAME.desc.direction
  end

  test "operators delegate to named methods (same op, same binds)" do
    assert_equal :eq, (UserSchema::NAME == "Alice").op
    assert_equal :neq, (UserSchema::NAME != "Bob").op
    assert_equal :gt, (UserSchema::AGE > 18).op
    assert_equal :gte, (UserSchema::AGE >= 18).op
    assert_equal :lt, (UserSchema::AGE < 65).op
    assert_equal :lte, (UserSchema::AGE <= 65).op
  end

  test "== and != work on every field type including BoolField" do
    assert_instance_of HakumiORM::Predicate, UserSchema::ACTIVE == true
    assert_instance_of HakumiORM::Predicate, UserSchema::ACTIVE != false
    assert_instance_of HakumiORM::Predicate, UserSchema::NAME == "x"
    assert_instance_of HakumiORM::Predicate, UserSchema::AGE == 1
  end

  test "comparison operators are absent on non-comparable fields" do
    refute_respond_to UserSchema::NAME, :>
    refute_respond_to UserSchema::NAME, :>=
    refute_respond_to UserSchema::NAME, :<
    refute_respond_to UserSchema::NAME, :<=
    refute_respond_to UserSchema::ACTIVE, :>
  end

  test "frozen fields still work correctly with operators" do
    field = UserSchema::AGE

    assert_predicate field, :frozen?
    assert_equal :eq, (field == 1).op
    assert_equal :gt, (field > 18).op
  end

  test "JsonField produces JsonBind and supports eq/neq/null" do
    field = HakumiORM::JsonField.new(:data, "t", "col", '"t"."col"')
    json = HakumiORM::Json.from_hash({ "a" => 1 })
    pred = field.eq(json)

    assert_instance_of HakumiORM::JsonBind, pred.binds[0]
    assert_equal :eq, pred.op

    refute_respond_to field, :gt
    refute_respond_to field, :like
    assert_respond_to field, :is_null
  end
end
