# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/migration"

class TestMigrationStructs < HakumiORM::TestCase
  test "ColumnDefinition stores name, type, and options" do
    col = HakumiORM::Migration::ColumnDefinition.new(
      name: "email",
      type: :string,
      null: false,
      default: nil,
      limit: 255,
      precision: nil,
      scale: nil
    )

    assert_equal "email", col.name
    assert_equal :string, col.type
    refute col.null
    assert_nil col.default
    assert_equal 255, col.limit
  end

  test "ColumnDefinition defaults null to true" do
    col = HakumiORM::Migration::ColumnDefinition.new(name: "age", type: :integer)

    assert col.null
    assert_nil col.default
    assert_nil col.limit
  end

  test "TableDefinition collects columns via DSL" do
    td = HakumiORM::Migration::TableDefinition.new("users")

    td.string "name", null: false
    td.integer "age"
    td.boolean "active", null: false, default: "true"

    assert_equal "users", td.name
    assert_equal :bigserial, td.id_type
    assert_equal 3, td.columns.length

    name_col = td.columns[0]

    assert_equal "name", name_col.name
    assert_equal :string, name_col.type
    refute name_col.null

    age_col = td.columns[1]

    assert_equal "age", age_col.name
    assert_equal :integer, age_col.type
    assert age_col.null

    active_col = td.columns[2]

    assert_equal "active", active_col.name
    assert_equal :boolean, active_col.type
    assert_equal "true", active_col.default
  end

  test "TableDefinition supports all column types" do
    td = HakumiORM::Migration::TableDefinition.new("test_types")

    %i[string text integer bigint float decimal boolean date datetime
       timestamp binary json jsonb uuid inet cidr hstore
       integer_array string_array float_array boolean_array].each do |type|
      td.column type.to_s, type
    end

    assert_equal 21, td.columns.length
    assert_equal :jsonb, td.columns.find { |c| c.name == "jsonb" }.type
    assert_equal :uuid, td.columns.find { |c| c.name == "uuid" }.type
  end

  test "TableDefinition#timestamps adds created_at and updated_at" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.timestamps

    assert_equal 2, td.columns.length
    assert_equal "created_at", td.columns[0].name
    assert_equal :timestamp, td.columns[0].type
    refute td.columns[0].null
    assert_equal "updated_at", td.columns[1].name
    assert_equal :timestamp, td.columns[1].type
    refute td.columns[1].null
  end

  test "TableDefinition#references adds foreign key column" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.references "users", foreign_key: true

    assert_equal 1, td.columns.length
    assert_equal "user_id", td.columns[0].name
    assert_equal :bigint, td.columns[0].type
    refute td.columns[0].null

    assert_equal 1, td.foreign_keys.length
    fk = td.foreign_keys[0]

    assert_equal "user_id", fk[:column]
    assert_equal "users", fk[:to_table]
    assert_equal "id", fk[:primary_key]
  end

  test "TableDefinition#references with nullable" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.references "categories", foreign_key: true, null: true

    col = td.columns[0]

    assert_equal "category_id", col.name
    assert col.null
  end

  test "TableDefinition with id: false omits primary key" do
    td = HakumiORM::Migration::TableDefinition.new("join_table", id: false)

    refute td.id_type
    td.integer "user_id", null: false
    td.integer "role_id", null: false

    assert_equal 2, td.columns.length
  end

  test "TableDefinition with id: :uuid uses UUID primary key" do
    td = HakumiORM::Migration::TableDefinition.new("tokens", id: :uuid)

    assert_equal :uuid, td.id_type
  end

  test "TableDefinition#column raises on unknown type" do
    td = HakumiORM::Migration::TableDefinition.new("users")

    err = assert_raises(HakumiORM::Error) do
      td.column "foo", :imaginary
    end

    assert_includes err.message, "Unknown column type"
    assert_includes err.message, ":imaginary"
  end

  test "TableDefinition#column accepts all known types" do
    td = HakumiORM::Migration::TableDefinition.new("test_types")

    %i[string text integer bigint float decimal boolean date datetime
       timestamp binary json jsonb uuid inet cidr hstore
       integer_array string_array float_array boolean_array].each do |type|
      td.column type.to_s, type
    end

    assert_equal 21, td.columns.length
  end

  test "TableDefinition#references with explicit column name" do
    td = HakumiORM::Migration::TableDefinition.new("enrollments")
    td.references "people", foreign_key: true, column: "person_id"

    col = td.columns[0]

    assert_equal "person_id", col.name
    assert_equal :bigint, col.type
    refute col.null

    fk = td.foreign_keys[0]

    assert_equal "person_id", fk[:column]
    assert_equal "people", fk[:to_table]
  end

  test "TableDefinition#references falls back to singularize when no column given" do
    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.references "categories", foreign_key: true

    assert_equal "category_id", td.columns[0].name
  end
end
