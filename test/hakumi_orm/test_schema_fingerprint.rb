# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/migration"

class TestSchemaFingerprint < HakumiORM::TestCase
  test "fingerprint is a 64-char hex string (SHA256)" do
    tables = build_tables
    fp = HakumiORM::Migration::SchemaFingerprint.compute(tables)

    assert_equal 64, fp.length
    assert_match(/\A[0-9a-f]{64}\z/, fp)
  end

  test "same schema produces same fingerprint" do
    fp1 = HakumiORM::Migration::SchemaFingerprint.compute(build_tables)
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute(build_tables)

    assert_equal fp1, fp2
  end

  test "different schemas produce different fingerprints" do
    tables1 = build_tables
    tables2 = build_tables
    tables2["users"].columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "bio", data_type: "text", udt_name: "text",
      nullable: true, default: nil, max_length: nil
    )

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute(tables1)
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute(tables2)

    refute_equal fp1, fp2
  end

  test "fingerprint is stable regardless of column insertion order" do
    table1 = HakumiORM::Codegen::TableInfo.new("users")
    table1.columns << col("age") << col("bio") << col("email")
    table1.primary_key = "id"

    table2 = HakumiORM::Codegen::TableInfo.new("users")
    table2.columns << col("email") << col("age") << col("bio")
    table2.primary_key = "id"

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table2 })

    assert_equal fp1, fp2
  end

  test "fingerprint is stable regardless of table insertion order" do
    tables1 = build_two_tables_order("posts", "users")
    tables2 = build_two_tables_order("users", "posts")

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute(tables1)
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute(tables2)

    assert_equal fp1, fp2
  end

  test "nullability change produces different fingerprint" do
    table1 = HakumiORM::Codegen::TableInfo.new("users")
    table1.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "email", data_type: "varchar", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )

    table2 = HakumiORM::Codegen::TableInfo.new("users")
    table2.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "email", data_type: "varchar", udt_name: "varchar",
      nullable: true, default: nil, max_length: 255
    )

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table2 })

    refute_equal fp1, fp2
  end

  test "default change produces different fingerprint" do
    table1 = HakumiORM::Codegen::TableInfo.new("users")
    table1.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "active", data_type: "boolean", udt_name: "bool",
      nullable: false, default: "true", max_length: nil
    )

    table2 = HakumiORM::Codegen::TableInfo.new("users")
    table2.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "active", data_type: "boolean", udt_name: "bool",
      nullable: false, default: "false", max_length: nil
    )

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table2 })

    refute_equal fp1, fp2
  end

  test "fingerprint includes generator version" do
    tables = build_tables
    fp1 = HakumiORM::Migration::SchemaFingerprint.compute(tables)

    original = HakumiORM::Migration::SchemaFingerprint::GENERATOR_VERSION
    begin
      HakumiORM::Migration::SchemaFingerprint.send(:remove_const, :GENERATOR_VERSION)
      HakumiORM::Migration::SchemaFingerprint.const_set(:GENERATOR_VERSION, "99")

      fp2 = HakumiORM::Migration::SchemaFingerprint.compute(build_tables)

      refute_equal fp1, fp2
    ensure
      HakumiORM::Migration::SchemaFingerprint.send(:remove_const, :GENERATOR_VERSION)
      HakumiORM::Migration::SchemaFingerprint.const_set(:GENERATOR_VERSION, original)
    end
  end

  test "foreign key change produces different fingerprint" do
    table1 = HakumiORM::Codegen::TableInfo.new("posts")
    table1.columns << col("title")
    table1.primary_key = "id"

    table2 = HakumiORM::Codegen::TableInfo.new("posts")
    table2.columns << col("title")
    table2.primary_key = "id"
    table2.foreign_keys << HakumiORM::Codegen::ForeignKeyInfo.new(
      column_name: "user_id", foreign_table: "users", foreign_column: "id"
    )

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "posts" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "posts" => table2 })

    refute_equal fp1, fp2
  end

  test "fingerprint is stable regardless of foreign key insertion order" do
    fk_a = HakumiORM::Codegen::ForeignKeyInfo.new(
      column_name: "author_id", foreign_table: "users", foreign_column: "id"
    )
    fk_b = HakumiORM::Codegen::ForeignKeyInfo.new(
      column_name: "author_id", foreign_table: "admins", foreign_column: "id"
    )

    table1 = HakumiORM::Codegen::TableInfo.new("posts")
    table1.columns << col("title")
    table1.primary_key = "id"
    table1.foreign_keys << fk_a << fk_b

    table2 = HakumiORM::Codegen::TableInfo.new("posts")
    table2.columns << col("title")
    table2.primary_key = "id"
    table2.foreign_keys << fk_b << fk_a

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "posts" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "posts" => table2 })

    assert_equal fp1, fp2
  end

  test "compute handles empty tables hash" do
    fp = HakumiORM::Migration::SchemaFingerprint.compute({})

    assert_equal 64, fp.length
    assert_match(/\A[0-9a-f]{64}\z/, fp)
  end

  test "compute handles table with no columns" do
    table = HakumiORM::Codegen::TableInfo.new("empty")

    fp = HakumiORM::Migration::SchemaFingerprint.compute({ "empty" => table })

    assert_equal 64, fp.length
  end

  test "check! raises SchemaDriftError on mismatch" do
    assert_raises(HakumiORM::SchemaDriftError) do
      HakumiORM::Migration::SchemaFingerprint.check!("abc123", "xyz789")
    end
  end

  test "check! does not raise when fingerprints match" do
    fp = HakumiORM::Migration::SchemaFingerprint.compute(build_tables)
    HakumiORM::Migration::SchemaFingerprint.check!(fp, fp)
  end

  test "check! warns instead of raising when HAKUMI_ALLOW_SCHEMA_DRIFT is set" do
    logger = Logger.new(StringIO.new)
    HakumiORM.config.logger = logger

    ENV["HAKUMI_ALLOW_SCHEMA_DRIFT"] = "1"
    HakumiORM::Migration::SchemaFingerprint.check!("abc123", "xyz789")
  ensure
    ENV.delete("HAKUMI_ALLOW_SCHEMA_DRIFT")
    HakumiORM.config.logger = nil
  end

  test "drift_allowed? returns false by default" do
    ENV.delete("HAKUMI_ALLOW_SCHEMA_DRIFT")

    refute_predicate HakumiORM::Migration::SchemaFingerprint, :drift_allowed?
  end

  test "drift_allowed? returns true when env var is set" do
    ENV["HAKUMI_ALLOW_SCHEMA_DRIFT"] = "1"

    assert_predicate HakumiORM::Migration::SchemaFingerprint, :drift_allowed?
  ensure
    ENV.delete("HAKUMI_ALLOW_SCHEMA_DRIFT")
  end

  private

  def col(name, type: "varchar", nullable: true)
    HakumiORM::Codegen::ColumnInfo.new(
      name: name, data_type: type, udt_name: type,
      nullable: nullable, default: nil, max_length: nil
    )
  end

  def build_tables
    table = HakumiORM::Codegen::TableInfo.new("users")
    table.columns << col("email", nullable: false)
    table.columns << col("name", nullable: false)
    table.primary_key = "id"
    { "users" => table }
  end

  def build_two_tables_order(first, second)
    posts = HakumiORM::Codegen::TableInfo.new("posts")
    posts.columns << col("title")
    posts.primary_key = "id"

    users = HakumiORM::Codegen::TableInfo.new("users")
    users.columns << col("name")
    users.primary_key = "id"

    tables = {}
    tables[first] = first == "posts" ? posts : users
    tables[second] = second == "posts" ? posts : users
    tables
  end
end
