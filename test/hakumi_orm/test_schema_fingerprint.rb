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

  test "store! creates table and inserts fingerprint and canonical" do
    adapter = HakumiORM::Test::MockAdapter.new
    fp = "a" * 64
    canonical = "V:1\nT:users|PK:id\nC:name|varchar|false|\n"

    HakumiORM::Migration::SchemaFingerprint.store!(adapter, fp, canonical)

    sqls = adapter.executed_queries.map { |q| q[:sql] }

    assert(sqls.any? { |s| s.include?("CREATE TABLE IF NOT EXISTS hakumi_schema_meta") })
    assert(sqls.any? { |s| s.include?("DELETE FROM hakumi_schema_meta") })
    assert(sqls.any? { |s| s.include?("INSERT INTO hakumi_schema_meta") && s.include?(fp) })
  end

  test "read_from_db returns fingerprint when present" do
    adapter = HakumiORM::Test::MockAdapter.new
    adapter.stub_result("SELECT fingerprint FROM hakumi_schema_meta", [["abc123def456"]])

    result = HakumiORM::Migration::SchemaFingerprint.read_from_db(adapter)

    assert_equal "abc123def456", result
  end

  test "read_from_db returns nil when table is empty" do
    adapter = HakumiORM::Test::MockAdapter.new

    result = HakumiORM::Migration::SchemaFingerprint.read_from_db(adapter)

    assert_nil result
  end

  test "read_from_db returns nil when table does not exist" do
    adapter = HakumiORM::Test::MockAdapter.new
    adapter.define_singleton_method(:exec) do |sql|
      raise StandardError, "relation does not exist" if sql.include?("hakumi_schema_meta")

      super(sql)
    end

    result = HakumiORM::Migration::SchemaFingerprint.read_from_db(adapter)

    assert_nil result
  end

  test "boot check raises SchemaDriftError on fingerprint mismatch" do
    adapter = HakumiORM::Test::MockAdapter.new
    adapter.stub_result("SELECT fingerprint FROM hakumi_schema_meta", [["db_fingerprint_999"]])

    config = HakumiORM.config
    config.schema_fingerprint = "manifest_fingerprint_111"
    config.adapter = adapter

    new_config = HakumiORM::Configuration.new
    new_config.schema_fingerprint = "manifest_fingerprint_111"
    new_config.database = "testdb"
    new_config.adapter_name = :sqlite

    assert_raises(HakumiORM::SchemaDriftError) do
      new_config.send(:verify_schema_fingerprint!, adapter)
    end
  ensure
    HakumiORM.reset_config!
  end

  test "boot check passes when fingerprints match" do
    adapter = HakumiORM::Test::MockAdapter.new
    fp = HakumiORM::Migration::SchemaFingerprint.compute(build_tables)
    adapter.stub_result("SELECT fingerprint FROM hakumi_schema_meta", [[fp]])

    config = HakumiORM::Configuration.new
    config.schema_fingerprint = fp

    config.send(:verify_schema_fingerprint!, adapter)
  end

  test "boot check skips when no schema_fingerprint set" do
    adapter = HakumiORM::Test::MockAdapter.new
    adapter.stub_result("SELECT fingerprint FROM hakumi_schema_meta", [["anything"]])

    config = HakumiORM::Configuration.new

    config.send(:verify_schema_fingerprint!, adapter)

    assert_empty adapter.executed_queries
  end

  test "boot check skips when meta table does not exist" do
    adapter = HakumiORM::Test::MockAdapter.new

    config = HakumiORM::Configuration.new
    config.schema_fingerprint = "some_fingerprint"

    config.send(:verify_schema_fingerprint!, adapter)
  end

  test "pending_migrations returns versions not yet applied" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "20240101000000_create_users.rb"), "")
      File.write(File.join(dir, "20240102000000_add_email.rb"), "")

      adapter = HakumiORM::Test::MockAdapter.new
      adapter.stub_result("SELECT version FROM hakumi_migrations", [["20240101000000"]])

      pending = HakumiORM::Migration::SchemaFingerprint.pending_migrations(adapter, dir)

      assert_equal ["20240102000000"], pending
    end
  end

  test "pending_migrations returns empty when all applied" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "20240101000000_create_users.rb"), "")

      adapter = HakumiORM::Test::MockAdapter.new
      adapter.stub_result("SELECT version FROM hakumi_migrations", [["20240101000000"]])

      pending = HakumiORM::Migration::SchemaFingerprint.pending_migrations(adapter, dir)

      assert_empty pending
    end
  end

  test "pending_migrations returns empty when dir does not exist" do
    adapter = HakumiORM::Test::MockAdapter.new

    pending = HakumiORM::Migration::SchemaFingerprint.pending_migrations(adapter, "/tmp/nonexistent_#{Process.pid}")

    assert_empty pending
  end

  test "pending_migrations returns all versions when table does not exist" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "20240101000000_create_users.rb"), "")

      adapter = HakumiORM::Test::MockAdapter.new
      adapter.define_singleton_method(:exec) do |sql|
        raise StandardError, "table does not exist" if sql.include?("hakumi_migrations")

        super(sql)
      end

      pending = HakumiORM::Migration::SchemaFingerprint.pending_migrations(adapter, dir)

      assert_equal ["20240101000000"], pending
    end
  end

  test "boot check raises PendingMigrationError when migrations pending" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "20240101000000_create_users.rb"), "")

      adapter = HakumiORM::Test::MockAdapter.new
      adapter.stub_result("SELECT fingerprint FROM hakumi_schema_meta", [["abc"]])

      config = HakumiORM::Configuration.new
      config.schema_fingerprint = "abc"
      config.migrations_path = dir

      assert_raises(HakumiORM::PendingMigrationError) do
        config.send(:verify_no_pending_migrations!, adapter)
      end
    end
  end

  test "boot check skips pending migration check when no schema_fingerprint set" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "20240101000000_create_users.rb"), "")

      adapter = HakumiORM::Test::MockAdapter.new

      config = HakumiORM::Configuration.new
      config.migrations_path = dir

      config.send(:verify_no_pending_migrations!, adapter)

      assert_empty adapter.executed_queries
    end
  end

  test "build_canonical returns deterministic string" do
    tables = build_tables
    c1 = HakumiORM::Migration::SchemaFingerprint.build_canonical(tables)
    c2 = HakumiORM::Migration::SchemaFingerprint.build_canonical(build_tables)

    assert_equal c1, c2
    assert_includes c1, "T:users|PK:id"
    assert_includes c1, "C:email|varchar|false|"
  end

  test "compute uses build_canonical internally" do
    tables = build_tables
    canonical = HakumiORM::Migration::SchemaFingerprint.build_canonical(tables)
    fp = HakumiORM::Migration::SchemaFingerprint.compute(tables)

    assert_equal Digest::SHA256.hexdigest(canonical), fp
  end

  test "read_canonical_from_db returns stored schema data" do
    adapter = HakumiORM::Test::MockAdapter.new
    adapter.stub_result("SELECT schema_data FROM hakumi_schema_meta", [["V:1\nT:users|PK:id\n"]])

    result = HakumiORM::Migration::SchemaFingerprint.read_canonical_from_db(adapter)

    assert_equal "V:1\nT:users|PK:id\n", result
  end

  test "read_canonical_from_db returns nil when empty" do
    adapter = HakumiORM::Test::MockAdapter.new

    result = HakumiORM::Migration::SchemaFingerprint.read_canonical_from_db(adapter)

    assert_nil result
  end

  test "diff_canonical detects added column" do
    stored = "V:1\nT:users|PK:id\nC:email|varchar|false|\nC:name|varchar|false|\n"
    live = "V:1\nT:users|PK:id\nC:age|integer|true|\nC:email|varchar|false|\nC:name|varchar|false|\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("+") && l.include?("age") })
  end

  test "diff_canonical detects removed column" do
    stored = "V:1\nT:users|PK:id\nC:email|varchar|false|\nC:name|varchar|false|\n"
    live = "V:1\nT:users|PK:id\nC:name|varchar|false|\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("-") && l.include?("email") })
  end

  test "diff_canonical detects type change" do
    stored = "V:1\nT:users|PK:id\nC:age|integer|true|\n"
    live = "V:1\nT:users|PK:id\nC:age|bigint|true|\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("-") && l.include?("integer") })
    assert(diff.any? { |l| l.include?("+") && l.include?("bigint") })
  end

  test "diff_canonical detects added table" do
    stored = "V:1\nT:users|PK:id\nC:name|varchar|false|\n"
    live = "V:1\nT:posts|PK:id\nC:title|varchar|true|\nT:users|PK:id\nC:name|varchar|false|\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("posts") })
  end

  test "diff_canonical returns empty when schemas match" do
    canonical = "V:1\nT:users|PK:id\nC:name|varchar|false|\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(canonical, canonical)

    assert_empty diff
  end

  test "diff_canonical formats FK lines" do
    stored = "V:1\nT:posts|PK:id\nC:title|varchar|true|\n"
    live = "V:1\nT:posts|PK:id\nC:title|varchar|true|\nFK:user_id->users.id\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("FK:") && l.include?("user_id") })
  end

  test "enum values change produces different fingerprint" do
    table1 = HakumiORM::Codegen::TableInfo.new("users")
    table1.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "role", data_type: "USER-DEFINED", udt_name: "role_enum",
      nullable: false, default: nil, max_length: nil,
      enum_values: %w[admin author]
    )
    table1.primary_key = "id"

    table2 = HakumiORM::Codegen::TableInfo.new("users")
    table2.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "role", data_type: "USER-DEFINED", udt_name: "role_enum",
      nullable: false, default: nil, max_length: nil,
      enum_values: %w[admin author moderator]
    )
    table2.primary_key = "id"

    fp1 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table1 })
    fp2 = HakumiORM::Migration::SchemaFingerprint.compute({ "users" => table2 })

    refute_equal fp1, fp2
  end

  test "build_canonical includes enum values in output" do
    table = HakumiORM::Codegen::TableInfo.new("users")
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "role", data_type: "USER-DEFINED", udt_name: "role_enum",
      nullable: false, default: nil, max_length: nil,
      enum_values: %w[admin author]
    )
    table.primary_key = "id"

    canonical = HakumiORM::Migration::SchemaFingerprint.build_canonical({ "users" => table })

    assert_includes canonical, "EV:admin,author"
  end

  test "build_canonical omits EV tag when no enum values" do
    table = HakumiORM::Codegen::TableInfo.new("users")
    table.columns << col("name", nullable: false)
    table.primary_key = "id"

    canonical = HakumiORM::Migration::SchemaFingerprint.build_canonical({ "users" => table })

    refute_includes canonical, "EV:"
  end

  test "diff_canonical detects enum value changes" do
    stored = "V:2\nT:users|PK:id\nC:role|USER-DEFINED|false||EV:admin,author\n"
    live = "V:2\nT:users|PK:id\nC:role|USER-DEFINED|false||EV:admin,author,moderator\n"

    diff = HakumiORM::Migration::SchemaFingerprint.diff_canonical(stored, live)

    assert(diff.any? { |l| l.include?("+") && l.include?("moderator") })
    assert(diff.any? { |l| l.include?("-") && l.include?("admin,author") })
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
