# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestCodegen < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new

    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('users_id_seq'::regclass)", max_length: nil
    )
    col_name = HakumiORM::Codegen::ColumnInfo.new(
      name: "name", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )
    col_email = HakumiORM::Codegen::ColumnInfo.new(
      name: "email", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )
    col_age = HakumiORM::Codegen::ColumnInfo.new(
      name: "age", data_type: "integer", udt_name: "int4",
      nullable: true, default: nil, max_length: nil
    )
    col_active = HakumiORM::Codegen::ColumnInfo.new(
      name: "active", data_type: "boolean", udt_name: "bool",
      nullable: false, default: "true", max_length: nil
    )

    table = HakumiORM::Codegen::TableInfo.new("users")
    table.columns << col_id << col_name << col_email << col_age << col_active
    table.primary_key = "id"

    @tables = { "users" => table }
  end

  test "generates singular folder with all required files" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      %w[
        user/checkable.rb user/schema.rb user/record.rb user/new_record.rb
        user/validated_record.rb user/base_contract.rb user/variant_base.rb
        user/relation.rb manifest.rb
      ].each do |file|
        assert_path_exists File.join(dir, file), "Missing #{file}"
      end
    end
  end

  test "schema has typed Field constants" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/schema.rb"))

      assert_includes code, "typed: strict"
      assert_includes code, "module UserSchema"
      assert_includes code, "::HakumiORM::IntField"
      assert_includes code, "::HakumiORM::StrField"
      assert_includes code, "::HakumiORM::BoolField"
      assert_includes code, "ID = T.let("
      assert_includes code, "NAME = T.let("
      assert_includes code, "ALL = T.let("
      assert_includes code, "TABLE_NAME"
    end
  end

  test "record has update! with dirty tracking and RETURNING" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, 'UPDATE "users" SET'
      assert_includes code, "RETURNING"
      assert_includes code, "def update!"
      assert_includes code, "Contract.on_update"
      assert_includes code, "Contract.on_all"
      assert_includes code, "Contract.on_persist"
      assert_includes code, "!= @", "update! should compare new values with current ivars for dirty tracking"
      assert_includes code, "return self if idx.zero?", "update! should return self when nothing changed"
    end
  end

  test "base_contract has on_update hook" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/base_contract.rb"))

      assert_includes code, "def self.on_update"
      assert_includes code, "UserRecord::Checkable"
    end
  end

  test "record has delete! with SQL_DELETE_BY_PK" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "SQL_DELETE_BY_PK"
      assert_includes code, 'DELETE FROM "users"'
      assert_includes code, "def delete!"
      assert_includes code, "affected_rows"
    end
  end

  test "record has to_h returning typed hash" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "def to_h"
      assert_includes code, "T::Hash[Symbol,"
      refute_includes code, "T.untyped"
    end
  end

  test "record has find_by and exists? class methods" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "def self.find_by"
      assert_includes code, "def self.exists?"
    end
  end

  test "record has typed attributes, keyword args, and hydration" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "typed: strict"
      assert_includes code, "class UserRecord"
      assert_includes code, "attr_reader :id"
      assert_includes code, "attr_reader :name"
      assert_includes code, "returns(Integer)"
      assert_includes code, "returns(String)"
      assert_includes code, "returns(T.nilable(Integer))"
      assert_includes code, "returns(T::Boolean)"
      assert_includes code, "def initialize(active:, age:, email:, id:, name:)"
      assert_includes code, "def self.from_result"
      assert_includes code, "def self.where"
      assert_includes code, "def self.all"
      assert_includes code, "def self.find"
      assert_includes code, "def self.build"
    end
  end

  test "new_record has insertable columns, validate!, and includes Checkable" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/new_record.rb"))

      assert_includes code, "typed: strict"
      assert_includes code, "class UserRecord"
      assert_includes code, "class New"
      assert_includes code, "include UserRecord::Checkable"
      assert_includes code, "attr_reader :name"
      assert_includes code, "attr_reader :email"
      assert_includes code, "attr_reader :age"
      assert_includes code, "attr_reader :active"
      refute_includes code, "attr_reader :id"
      assert_includes code, "def validate!"
      assert_includes code, "UserRecord::Validated.new(self)"
      refute_includes code, "def save!"
      refute_includes code, "SQL_INSERT"
    end
  end

  test "relation references Record and Schema" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes code, "typed: strict"
      assert_includes code, "class UserRelation < ::HakumiORM::Relation"
      assert_includes code, "ModelType = type_member {{ fixed: UserRecord }}"
      assert_includes code, "UserSchema::TABLE_NAME"
      assert_includes code, "UserRecord.from_result"
      assert_includes code, "def stmt_count_all"
      assert_includes code, "def sql_count_all"
      assert_includes code, 'SELECT COUNT(*) FROM "users"'
    end
  end

  test "generated code contains zero T.untyped, T.unsafe, and T.must" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      %w[
        user/checkable.rb user/schema.rb user/record.rb user/new_record.rb
        user/validated_record.rb user/base_contract.rb user/variant_base.rb
        user/relation.rb
      ].each do |file|
        code = File.read(File.join(dir, file))

        refute_includes code, "T.untyped", "#{file} contains T.untyped"
        refute_includes code, "T.unsafe", "#{file} contains T.unsafe"
        refute_includes code, "T.must", "#{file} contains T.must"
      end
    end
  end

  test "generated code with module_name wraps in module" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir, module_name: "App"))
      gen.generate!

      schema_code = File.read(File.join(dir, "user/schema.rb"))
      record_code = File.read(File.join(dir, "user/record.rb"))
      rel_code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes schema_code, "module App"
      assert_includes record_code, "module App"
      assert_includes rel_code, "module App"
      assert_includes rel_code, "App::UserRecord"
    end
  end

  test "manifest requires files in correct order" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "manifest.rb"))

      %w[checkable schema record new_record validated_record base_contract variant_base relation].each do |name|
        assert_includes code, "require_relative \"user/#{name}\""
      end
    end
  end

  test "manifest includes schema_fingerprint when provided" do
    Dir.mktmpdir do |dir|
      fp = "a1b2c3d4" * 8
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir, schema_fingerprint: fp))
      gen.generate!

      code = File.read(File.join(dir, "manifest.rb"))

      assert_includes code, "HakumiORM.config.schema_fingerprint = \"#{fp}\""
    end
  end

  test "manifest omits schema_fingerprint when not provided" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "manifest.rb"))

      refute_includes code, "schema_fingerprint"
    end
  end

  test "variant_base delegates all columns including pk" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/variant_base.rb"))

      assert_includes code, "class VariantBase"
      assert_includes code, "def id = @record.id"
      assert_includes code, "def name = @record.name"
      assert_includes code, "def age = @record.age"
      assert_includes code, "returns(T.nilable(Integer))"
      assert_includes code, "returns(Integer)"
      assert_includes code, "returns(String)"
      assert_includes code, "params(record: UserRecord)"
      assert_includes code, "def initialize(record:)"
      assert_includes code, "attr_reader :record"
      refute_includes code, "T.must"
    end
  end

  test "validated_record has SQL_INSERT with RETURNING, save!, and on_persist" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/validated_record.rb"))

      assert_includes code, "SQL_INSERT"
      refute_includes code, '"id") VALUES'
      assert_includes code, "RETURNING"
      assert_includes code, "def save!"
      assert_includes code, "UserRecord::Contract.on_persist"
      assert_includes code, "include UserRecord::Checkable"
    end
  end

  test "models_dir generates model stubs that inherit from Record" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      model_path = File.join(models_dir, "user.rb")

      assert_path_exists model_path, "Missing models/user.rb"

      code = File.read(model_path)

      assert_includes code, "class User < UserRecord"
      assert_includes code, "typed: strict"
    end
  end

  test "model stub has doc link and inherits from record" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "class User < UserRecord"
      assert_includes code, "docs/models.md"
    end
  end

  test "models_dir preserves user code and adds annotation" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")
      FileUtils.mkdir_p(models_dir)

      custom_code = "class User < UserRecord\n  def custom_method; end\nend\n"
      File.write(File.join(models_dir, "user.rb"), custom_code)

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      result = File.read(File.join(models_dir, "user.rb"))

      assert_includes result, "def custom_method; end"
      assert_includes result, "# == Schema Information =="
      assert_includes result, "# Table name: users"
    end
  end

  test "checkable generates an interface module with abstract field readers" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/checkable.rb"))

      assert_includes code, "module Checkable"
      assert_includes code, "interface!"
      assert_includes code, "abstract.returns(String)"
      assert_includes code, "def name; end"
      assert_includes code, "def email; end"
      assert_includes code, "def active; end"
      assert_includes code, "def age; end"
    end
  end

  test "base_contract has overridable on_all, on_create, on_persist" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/base_contract.rb"))

      assert_includes code, "class UserRecord::BaseContract"
      assert_includes code, "abstract!"
      assert_includes code, "overridable"
      assert_includes code, "def self.on_all(_record, _e)"
      assert_includes code, "def self.on_create(_record, _e)"
      assert_includes code, "def self.on_persist(_record, _adapter, _e)"
      assert_includes code, "UserRecord::Checkable"
      assert_includes code, "UserRecord::New"
    end
  end

  test "contracts_dir generates contract stubs extending BaseContract" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      contracts_dir = File.join(dir, "contracts")

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, contracts_dir: contracts_dir))
      gen.generate!

      contract_path = File.join(contracts_dir, "user_contract.rb")

      assert_path_exists contract_path, "Missing contracts/user_contract.rb"

      code = File.read(contract_path)

      assert_includes code, "class UserRecord::Contract < UserRecord::BaseContract"
      assert_includes code, "typed: strict"
    end
  end

  test "validated_record uses Time.now for created_at and updated_at on insert" do
    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('posts_id_seq'::regclass)", max_length: nil
    )
    col_title = HakumiORM::Codegen::ColumnInfo.new(
      name: "title", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )
    col_created = HakumiORM::Codegen::ColumnInfo.new(
      name: "created_at", data_type: "timestamp with time zone", udt_name: "timestamptz",
      nullable: false, default: nil, max_length: nil
    )
    col_updated = HakumiORM::Codegen::ColumnInfo.new(
      name: "updated_at", data_type: "timestamp with time zone", udt_name: "timestamptz",
      nullable: false, default: nil, max_length: nil
    )

    table = HakumiORM::Codegen::TableInfo.new("posts")
    table.columns << col_id << col_title << col_created << col_updated
    table.primary_key = "id"

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "posts" => table }, opts(dir))
      gen.generate!

      validated_code = File.read(File.join(dir, "post/validated_record.rb"))

      assert_includes validated_code, "TimeBind.new(::Time.now)", "save! should auto-set created_at/updated_at"

      record_code = File.read(File.join(dir, "post/record.rb"))

      assert_includes record_code, "def update!"
      assert_includes record_code, "TimeBind.new(::Time.now)", "update! should auto-set updated_at"
    end
  end

  test "timestamps are not auto-set for non-timestamp columns named created_at" do
    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('logs_id_seq'::regclass)", max_length: nil
    )
    col_created = HakumiORM::Codegen::ColumnInfo.new(
      name: "created_at", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )

    table = HakumiORM::Codegen::TableInfo.new("logs")
    table.columns << col_id << col_created
    table.primary_key = "id"

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "logs" => table }, opts(dir))
      gen.generate!

      validated_code = File.read(File.join(dir, "log/validated_record.rb"))

      refute_includes validated_code, "Time.now", "Non-timestamp created_at should not auto-set"
    end
  end

  test "contracts_dir does not overwrite existing contract files" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      contracts_dir = File.join(dir, "contracts")
      FileUtils.mkdir_p(contracts_dir)

      custom_code = "class UserRecord::Contract < UserRecord::BaseContract\n  # custom\nend\n"
      File.write(File.join(contracts_dir, "user_contract.rb"), custom_code)

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, contracts_dir: contracts_dir))
      gen.generate!

      assert_equal custom_code, File.read(File.join(contracts_dir, "user_contract.rb"))
    end
  end

  test "models_dir with module_name wraps model in module" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      gen = HakumiORM::Codegen::Generator.new(@tables, opts(gen_dir, models_dir: models_dir, module_name: "App"))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "module App"
      assert_includes code, "class App::User < App::UserRecord"
    end
  end

  test "has_many generates association method and preload" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def posts"
      assert_includes user_code, "PostRelation"
      assert_includes user_code, "def self.preload_posts"
    end
  end

  test "has_many preload sets inverse belongs_to" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "child._preloaded_user = [parent] if parent"
    end
  end

  test "has_one preload sets inverse belongs_to" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "child._preloaded_user = [parent] if parent"
    end
  end

  test "has_one generates singular accessor when FK has unique constraint" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def profile"
      assert_includes user_code, "T.nilable(ProfileRecord)"
      assert_includes user_code, "def self.preload_profile"
      refute_includes user_code, "def profiles"
    end
  end

  test "has_one preload indexes by FK and stores single record" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "related ? [related] : []"
    end
  end

  test "belongs_to generates accessor and preload" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      post_code = File.read(File.join(dir, "post/record.rb"))

      assert_includes post_code, "def user"
      assert_includes post_code, "T.nilable(UserRecord)"
      assert_includes post_code, "def self.preload_user"
    end
  end

  test "relation includes has_one in preloadable assocs" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      rel_code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes rel_code, "when :profile"
      assert_includes rel_code, "preload_profile"
    end
  end

  test "relation run_preloads dispatches nested and delegates unknown to custom_preload" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      rel_code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes rel_code, "PreloadNode"
      assert_includes rel_code, "node.name"
      assert_includes rel_code, "node.children"
      assert_includes rel_code, "PostRelation.new.run_preloads"
      assert_includes rel_code, "custom_preload(node.name, records, adapter)"
    end
  end

  test "relation run_preloads generated for table without FK-based associations" do
    table = HakumiORM::Codegen::TableInfo.new("settings")
    table.columns << HakumiORM::Codegen::ColumnInfo.new(name: "id", data_type: "integer", udt_name: "int4", nullable: false)
    table.columns << HakumiORM::Codegen::ColumnInfo.new(name: "key", data_type: "character varying", udt_name: "varchar", nullable: false)
    table.primary_key = "id"
    tables = { "settings" => table }
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      rel_code = File.read(File.join(dir, "setting/relation.rb"))

      assert_includes rel_code, "run_preloads"
      assert_includes rel_code, "custom_preload(node.name, records, adapter)"
    end
  end

  test "has_many through join table generates subquery method" do
    tables = build_users_roles_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def roles"
      assert_includes user_code, "SubqueryExpr"
      assert_includes user_code, "UsersRoleRelation"
      assert_includes user_code, "UsersRoleSchema::USER_ID"
      assert_includes user_code, "UsersRoleSchema::ROLE_ID"
      assert_includes user_code, "RoleSchema::ID"
      assert_includes user_code, "returns(RoleRelation)"
    end
  end

  test "delete! with dependent generates delete_all and destroy branches" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "SQL_DELETE_POSTS"
      assert_includes user_code, "dependent: :none"
      assert_includes user_code, "when :delete_all"
      assert_includes user_code, "when :destroy"
      assert_includes user_code, "posts.to_a(adapter: adapter).each"
    end
  end

  test "delete! without associations has no dependent parameter" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def delete!(adapter:"
      refute_includes user_code, "dependent:"
    end
  end

  test "delete! with has_one generates destroy with safe navigation" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "SQL_DELETE_PROFILE"
      assert_includes user_code, "profile(adapter: adapter)&.delete!"
    end
  end

  test "has_many through chain generates subquery method" do
    tables = build_users_posts_comments_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def comments"
      assert_includes user_code, "SubqueryExpr"
      assert_includes user_code, "PostRelation"
      assert_includes user_code, "PostSchema::USER_ID"
      assert_includes user_code, "PostSchema::ID"
      assert_includes user_code, "CommentSchema::POST_ID"
    end
  end

  test "has_many through generates both directions for join table" do
    tables = build_users_roles_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      role_code = File.read(File.join(dir, "role/record.rb"))

      assert_includes role_code, "def users"
      assert_includes role_code, "SubqueryExpr"
      assert_includes role_code, "UsersRoleSchema::ROLE_ID"
      assert_includes role_code, "UsersRoleSchema::USER_ID"
      assert_includes role_code, "UserSchema::ID"
    end
  end

  test "has_many through name collisions are disambiguated" do
    tables = build_tasks_attachments_comments_users_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      task_code = File.read(File.join(dir, "task/record.rb"))

      assert_equal 1, task_code.scan("def users(adapter: ::HakumiORM.adapter)").length
      assert_includes task_code, "def users_via_comment(adapter: ::HakumiORM.adapter)"
      assert_includes task_code, "AttachmentRelation"
      assert_includes task_code, "CommentRelation"
    end
  end

  test "has_one through generates singular method with first" do
    tables = build_users_profiles_avatars_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def avatar"
      assert_includes user_code, "SubqueryExpr"
      assert_includes user_code, "ProfileRelation"
      assert_includes user_code, "ProfileSchema::USER_ID"
      assert_includes user_code, ".first(adapter: adapter)"
      assert_includes user_code, "returns(T.nilable(AvatarRecord))"
      refute_includes user_code, "returns(AvatarRelation)"
    end
  end

  test "has_many through remains plural without unique constraints" do
    tables = build_users_roles_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def roles"
      assert_includes user_code, "returns(RoleRelation)"
      refute_includes user_code, "returns(T.nilable(RoleRecord))"
    end
  end

  test "optimistic locking adds lock_version to UPDATE WHERE clause" do
    tables = build_table_with_lock_version
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "product/record.rb"))

      assert_includes code, '"lock_version" = "lock_version" + 1'
      assert_includes code, '"products"."lock_version" ='
      assert_includes code, "StaleObjectError"
      assert_includes code, "@lock_version"
    end
  end

  test "optimistic locking excludes lock_version from update! parameters" do
    tables = build_table_with_lock_version
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "product/record.rb"))

      assert_match(/def update!\(name:/, code)
      refute_match(/def update!.*lock_version:/, code)
    end
  end

  test "tables without lock_version do not use StaleObjectError" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      refute_includes code, "StaleObjectError"
      refute_includes code, "lock_version"
    end
  end

  test "json column generates JsonField and Cast.to_json" do
    tables = build_table_with_json
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      schema = File.read(File.join(dir, "event/schema.rb"))
      record = File.read(File.join(dir, "event/record.rb"))

      assert_includes schema, "::HakumiORM::JsonField"
      assert_includes record, "::HakumiORM::Json"
      assert_includes record, "dialect.cast_json"
    end
  end

  test "schema escapes double quotes in postgresql qualified names" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/schema.rb"))

      assert_includes code, '\"users\".\"name\"'
      assert_includes code, '\"users\".\"email\"'
      assert_includes code, '\"users\".\"id\"'
    end
  end

  test "schema escapes double quotes in sqlite qualified names" do
    dialect = HakumiORM::Dialect::Sqlite.new
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir, dialect: dialect))
      gen.generate!

      code = File.read(File.join(dir, "user/schema.rb"))

      assert_includes code, '\"users\".\"name\"'
      assert_includes code, '\"users\".\"email\"'
    end
  end

  test "schema uses backticks for mysql qualified names without extra escaping" do
    dialect = HakumiORM::Dialect::Mysql.new
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir, dialect: dialect))
      gen.generate!

      code = File.read(File.join(dir, "user/schema.rb"))

      assert_includes code, "`users`.`name`"
      assert_includes code, "`users`.`email`"
      refute_includes code, '\\"'
    end
  end

  test "schema escapes backslashes before double quotes in qualified names" do
    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('weird_id_seq'::regclass)", max_length: nil
    )
    col_val = HakumiORM::Codegen::ColumnInfo.new(
      name: "val", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )

    table = HakumiORM::Codegen::TableInfo.new("weird")
    table.columns << col_id << col_val
    table.primary_key = "id"

    dialect = Class.new(HakumiORM::Dialect::Postgresql) do
      define_method(:qualified_name) do |tbl, col|
        "\"#{tbl}\\\".\"#{col}\""
      end
    end.new

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "weird" => table }, opts(dir, dialect: dialect))
      gen.generate!

      code = File.read(File.join(dir, "weird/schema.rb"))

      assert_includes code, '\\\\\"'
    end
  end

  test "as_json generates hash with string keys and JSON-safe values" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "def as_json(only: nil, except: nil)"
      assert_includes code, 'h["id"]'
      assert_includes code, 'h["name"]'
      assert_includes code, 'h["active"]'
      assert_includes code, "T::Hash[String,"
      assert_includes code, "only && !only.include?"
      assert_includes code, "except&.include?"
    end
  end

  test "as_json converts timestamps to iso8601" do
    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('events_id_seq'::regclass)", max_length: nil
    )
    col_created = HakumiORM::Codegen::ColumnInfo.new(
      name: "created_at", data_type: "timestamp with time zone", udt_name: "timestamptz",
      nullable: false, default: nil, max_length: nil
    )
    col_deleted = HakumiORM::Codegen::ColumnInfo.new(
      name: "deleted_at", data_type: "timestamp with time zone", udt_name: "timestamptz",
      nullable: true, default: nil, max_length: nil
    )

    table = HakumiORM::Codegen::TableInfo.new("events")
    table.columns << col_id << col_created << col_deleted
    table.primary_key = "id"

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "events" => table }, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "event/record.rb"))

      assert_includes code, "@created_at.iso8601(6)"
      assert_includes code, "@deleted_at&.iso8601(6)"
    end
  end

  test "as_json converts decimal to string and json to raw_json" do
    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: "nextval('items_id_seq'::regclass)", max_length: nil
    )
    col_price = HakumiORM::Codegen::ColumnInfo.new(
      name: "price", data_type: "numeric", udt_name: "numeric",
      nullable: false, default: nil, max_length: nil
    )
    col_meta = HakumiORM::Codegen::ColumnInfo.new(
      name: "meta", data_type: "jsonb", udt_name: "jsonb",
      nullable: true, default: nil, max_length: nil
    )

    table = HakumiORM::Codegen::TableInfo.new("items")
    table.columns << col_id << col_price << col_meta
    table.primary_key = "id"

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "items" => table }, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "item/record.rb"))

      assert_includes code, '@price.to_s("F")'
      assert_includes code, "@meta&.raw_json"
    end
  end

  test "as_json has zero T.untyped, T.unsafe, T.must" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      refute_includes code, "T.untyped"
      refute_includes code, "T.unsafe"
      refute_includes code, "T.must"
    end
  end

  test "variant_base delegates as_json and to_h" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      code = File.read(File.join(dir, "user/variant_base.rb"))

      assert_includes code, "def to_h = @record.to_h"
      assert_includes code, "def as_json(only: nil, except: nil) = @record.as_json(only: only, except: except)"
    end
  end

  test "uuid column generates StrField" do
    tables = build_table_with_uuid
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      schema = File.read(File.join(dir, "token/schema.rb"))
      record = File.read(File.join(dir, "token/record.rb"))

      assert_includes schema, "::HakumiORM::StrField"
      assert_includes record, "returns(String)"
    end
  end

  test "record generates diff and changed_from? methods" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def changed_from?(other)"
      assert_includes record, "def diff(other)"
      assert_includes record, "@name != other.name"
    end
  end

  test "variant_base delegates diff and changed_from?" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      variant = File.read(File.join(dir, "user/variant_base.rb"))

      assert_includes variant, "def changed_from?(other)"
      assert_includes variant, "def diff(other)"
    end
  end

  test "soft delete generates delete! as UPDATE and really_delete! as DELETE" do
    tables = build_table_with_soft_delete
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir, soft_delete_tables: { "articles" => "deleted_at" }))
      gen.generate!

      record = File.read(File.join(dir, "article/record.rb"))

      assert_includes record, "SQL_SOFT_DELETE_BY_PK"
      assert_includes record, "def delete!"
      assert_includes record, "def really_delete!"
      assert_includes record, "def deleted?"
      assert_includes record, "SQL_SOFT_DELETE_BY_PK"
      assert_includes record, "SQL_DELETE_BY_PK"
    end
  end

  test "soft delete relation adds default scope and with_deleted/only_deleted" do
    tables = build_table_with_soft_delete
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir, soft_delete_tables: { "articles" => "deleted_at" }))
      gen.generate!

      relation = File.read(File.join(dir, "article/relation.rb"))

      assert_includes relation, "DELETED_AT.is_null"
      assert_includes relation, "def with_deleted"
      assert_includes relation, "def only_deleted"
      assert_includes relation, "DELETED_AT.is_not_null"
    end
  end

  test "soft delete count SQL includes deleted_at IS NULL" do
    tables = build_table_with_soft_delete
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir, soft_delete_tables: { "articles" => "deleted_at" }))
      gen.generate!

      relation = File.read(File.join(dir, "article/relation.rb"))

      assert_includes relation, "IS NULL"
      assert_includes relation, "deleted_at"
    end
  end

  test "table without deleted_at does not get soft delete features" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "user/record.rb"))
      relation = File.read(File.join(dir, "user/relation.rb"))

      refute_includes record, "really_delete!"
      refute_includes record, "SQL_SOFT_DELETE"
      refute_includes relation, "with_deleted"
      refute_includes relation, "only_deleted"
    end
  end

  test "table with deleted_at but not in soft_delete_tables does not get soft delete" do
    tables = build_table_with_soft_delete
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "article/record.rb"))
      relation = File.read(File.join(dir, "article/relation.rb"))

      refute_includes record, "really_delete!"
      refute_includes record, "SQL_SOFT_DELETE"
      refute_includes relation, "with_deleted"
      refute_includes relation, "only_deleted"
    end
  end

  test "soft delete with custom column name uses that column in generated code" do
    tables = build_table_with_custom_soft_delete
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir, soft_delete_tables: { "events" => "removed_at" }))
      gen.generate!

      record = File.read(File.join(dir, "event/record.rb"))
      relation = File.read(File.join(dir, "event/relation.rb"))

      assert_includes record, "def deleted?"
      assert_includes record, "@removed_at.nil?"
      assert_includes record, "SQL_SOFT_DELETE_BY_PK"
      assert_includes relation, "REMOVED_AT.is_null"
      assert_includes relation, "REMOVED_AT.is_not_null"
      assert_includes relation, "def with_deleted"
      assert_includes relation, "def only_deleted"

      refute_includes relation, "DELETED_AT"
    end
  end

  test "enum column generates T::Enum class file" do
    tables = build_table_with_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      enum_code = File.read(File.join(dir, "post/status_enum.rb"))

      assert_includes enum_code, "class PostStatusEnum < T::Enum"
      assert_includes enum_code, 'DRAFT = new("draft")'
      assert_includes enum_code, 'PUBLISHED = new("published")'
      assert_includes enum_code, 'ARCHIVED = new("archived")'
    end
  end

  test "enum column generates EnumField in schema" do
    tables = build_table_with_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      schema = File.read(File.join(dir, "post/schema.rb"))

      assert_includes schema, "::HakumiORM::EnumField[PostStatusEnum]"
    end
  end

  test "enum column types record attr as the enum class" do
    tables = build_table_with_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "post/record.rb"))

      assert_includes record, "returns(PostStatusEnum)"
      assert_includes record, "PostStatusEnum.deserialize"
    end
  end

  test "nullable enum column generates T.nilable type and safe cast" do
    tables = build_table_with_nullable_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "task/record.rb"))

      assert_includes record, "returns(T.nilable(TaskPriorityEnum))"
      assert_includes record, "TaskPriorityEnum.deserialize(_hv)"
    end
  end

  test "enum manifest requires enum files before table files" do
    tables = build_table_with_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      manifest = File.read(File.join(dir, "manifest.rb"))
      enum_pos = manifest.index("post/status_enum")
      table_pos = manifest.index("post/schema")

      refute_nil enum_pos
      refute_nil table_pos
      assert_operator enum_pos, :<, table_pos
    end
  end

  test "enum as_json serializes to string" do
    tables = build_table_with_enum
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "post/record.rb"))

      assert_includes record, "@status.serialize"
    end
  end

  private

  def col(name, type: "integer", udt: "int4", nullable: false, default: nil, max_length: nil)
    HakumiORM::Codegen::ColumnInfo.new(
      name: name, data_type: type, udt_name: udt,
      nullable: nullable, default: default, max_length: max_length
    )
  end

  def pk_col(table_name)
    col("id", default: "nextval('#{table_name}_id_seq'::regclass)")
  end

  def str_col(name)
    col(name, type: "character varying", udt: "varchar", max_length: 255)
  end

  def fk_col(name)
    col(name)
  end

  def enum_col(name, udt_name, values, nullable: false)
    HakumiORM::Codegen::ColumnInfo.new(
      name: name, data_type: "USER-DEFINED", udt_name: udt_name,
      nullable: nullable, default: nil, max_length: nil, enum_values: values
    )
  end

  def fk(column_name, foreign_table, foreign_column = "id")
    HakumiORM::Codegen::ForeignKeyInfo.new(
      column_name: column_name, foreign_table: foreign_table, foreign_column: foreign_column
    )
  end

  def make_table(name, columns:, pk: "id", fks: [], unique: [])
    table = HakumiORM::Codegen::TableInfo.new(name)
    columns.each { |c| table.columns << c }
    table.primary_key = pk
    fks.each { |f| table.foreign_keys << f }
    unique.each { |u| table.unique_columns << u }
    table
  end

  def build_users_and_posts_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    posts = make_table("posts",
                       columns: [pk_col("posts"), fk_col("user_id"), str_col("title")],
                       fks: [fk("user_id", "users")])
    { "users" => users, "posts" => posts }
  end

  def build_users_and_profile_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    profiles = make_table("profiles",
                          columns: [pk_col("profiles"), fk_col("user_id"),
                                    col("bio", type: "text", udt: "text", nullable: true)],
                          fks: [fk("user_id", "users")],
                          unique: ["user_id"])
    { "users" => users, "profiles" => profiles }
  end

  def build_users_roles_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    roles = make_table("roles", columns: [pk_col("roles"), str_col("name")])
    users_roles = make_table("users_roles",
                             columns: [pk_col("users_roles"), fk_col("user_id"), fk_col("role_id")],
                             fks: [fk("user_id", "users"), fk("role_id", "roles")])
    { "users" => users, "roles" => roles, "users_roles" => users_roles }
  end

  def build_table_with_lock_version
    products = make_table("products",
                          columns: [pk_col("products"), str_col("name"),
                                    col("lock_version", default: "0")])
    { "products" => products }
  end

  def build_table_with_json
    events = make_table("events",
                        columns: [pk_col("events"), str_col("name"),
                                  col("payload", type: "jsonb", udt: "jsonb", nullable: true)])
    { "events" => events }
  end

  def build_table_with_uuid
    tokens = make_table("tokens",
                        columns: [pk_col("tokens"),
                                  col("token_id", type: "uuid", udt: "uuid")])
    { "tokens" => tokens }
  end

  def build_users_profiles_avatars_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    profiles = make_table("profiles",
                          columns: [pk_col("profiles"), fk_col("user_id"), str_col("bio")],
                          fks: [fk("user_id", "users")],
                          unique: ["user_id"])
    avatars = make_table("avatars",
                         columns: [pk_col("avatars"), fk_col("profile_id"), str_col("url")],
                         fks: [fk("profile_id", "profiles")],
                         unique: ["profile_id"])
    { "users" => users, "profiles" => profiles, "avatars" => avatars }
  end

  def build_table_with_soft_delete
    articles = make_table("articles",
                          columns: [pk_col("articles"), str_col("title"),
                                    col("deleted_at", type: "timestamp with time zone", udt: "timestamptz", nullable: true)])
    { "articles" => articles }
  end

  def build_table_with_custom_soft_delete
    events = make_table("events",
                        columns: [pk_col("events"), str_col("name"),
                                  col("removed_at", type: "timestamp with time zone", udt: "timestamptz", nullable: true)])
    { "events" => events }
  end

  def build_table_with_enum
    posts = make_table("posts",
                       columns: [pk_col("posts"), str_col("title"),
                                 enum_col("status", "post_status", %w[draft published archived])])
    { "posts" => posts }
  end

  def build_table_with_nullable_enum
    tasks = make_table("tasks",
                       columns: [pk_col("tasks"), str_col("name"),
                                 enum_col("priority", "task_priority", %w[low medium high], nullable: true)])
    { "tasks" => tasks }
  end

  def build_users_posts_comments_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    posts = make_table("posts",
                       columns: [pk_col("posts"), fk_col("user_id"), str_col("title")],
                       fks: [fk("user_id", "users")])
    comments = make_table("comments",
                          columns: [pk_col("comments"), fk_col("post_id"),
                                    col("body", type: "text", udt: "text")],
                          fks: [fk("post_id", "posts")])
    { "users" => users, "posts" => posts, "comments" => comments }
  end

  def build_tasks_attachments_comments_users_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    tasks = make_table("tasks", columns: [pk_col("tasks"), str_col("title")])
    attachments = make_table("attachments",
                             columns: [pk_col("attachments"), fk_col("task_id"), fk_col("uploader_id")],
                             fks: [fk("task_id", "tasks"), fk("uploader_id", "users")])
    comments = make_table("comments",
                          columns: [pk_col("comments"), fk_col("task_id"), fk_col("author_id")],
                          fks: [fk("task_id", "tasks"), fk("author_id", "users")])
    {
      "users" => users,
      "tasks" => tasks,
      "attachments" => attachments,
      "comments" => comments
    }
  end

  def build_enum_definition(column:, values:, prefix: nil, suffix: nil)
    HakumiORM::Codegen::EnumDefinition.new(
      column_name: column, values: values, prefix: prefix, suffix: suffix
    )
  end

  def opts(dir, **overrides)
    HakumiORM::Codegen::GeneratorOptions.new(dialect: @dialect, output_dir: dir, **overrides)
  end
end

class TestUserDefinedEnums < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Sqlite.new

    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "INTEGER", udt_name: "INTEGER",
      nullable: true, default: nil, max_length: nil
    )
    col_name = HakumiORM::Codegen::ColumnInfo.new(
      name: "name", data_type: "TEXT", udt_name: "TEXT",
      nullable: false, default: nil, max_length: nil
    )
    col_role = HakumiORM::Codegen::ColumnInfo.new(
      name: "role", data_type: "INTEGER", udt_name: "INTEGER",
      nullable: false, default: nil, max_length: nil
    )
    col_status = HakumiORM::Codegen::ColumnInfo.new(
      name: "status", data_type: "INTEGER", udt_name: "INTEGER",
      nullable: false, default: nil, max_length: nil
    )

    table = HakumiORM::Codegen::TableInfo.new("users")
    table.columns << col_id << col_name << col_role << col_status
    table.primary_key = "id"

    @tables = { "users" => table }
    @role_enum = HakumiORM::Codegen::EnumDefinition.new(
      column_name: "role",
      values: { admin: 0, author: 1, reader: 2 },
      prefix: :role
    )
    @status_enum = HakumiORM::Codegen::EnumDefinition.new(
      column_name: "status",
      values: { active: 0, banned: 1 },
      suffix: :status
    )
    @user_enums = { "users" => [@role_enum, @status_enum] }
  end

  def teardown
    HakumiORM.reset_config!
  end

  test "EnumBuilder DSL parses key-value enums with prefix/suffix" do
    builder = HakumiORM::Codegen::EnumBuilder.new("users")
    builder.enum(:role, { admin: 0, author: 1, reader: 2 }, prefix: :role)
    builder.enum(:status, { active: 0, banned: 1 }, suffix: :status)

    assert_equal 2, builder.definitions.length

    role = builder.definitions[0]

    assert_equal "role", role.column_name
    assert_equal({ admin: 0, author: 1, reader: 2 }, role.values)
    assert_equal :role, role.prefix
    assert_nil role.suffix

    status = builder.definitions[1]

    assert_equal "status", status.column_name
    assert_equal({ active: 0, banned: 1 }, status.values)
    assert_nil status.prefix
    assert_equal :status, status.suffix
  end

  test "EnumBuilder raises on empty values" do
    builder = HakumiORM::Codegen::EnumBuilder.new("users")

    assert_raises(HakumiORM::Error) { builder.enum(:role, {}) }
  end

  test "EnumDefinition#serialized_values returns string representations" do
    assert_equal %w[0 1 2], @role_enum.serialized_values
    assert_equal %w[0 1], @status_enum.serialized_values
  end

  test "generates enum files from user-defined enums" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      role_enum_path = File.join(dir, "user", "role_enum.rb")

      assert_path_exists role_enum_path

      content = File.read(role_enum_path)

      assert_includes content, "class UserRoleEnum < T::Enum"
      assert_includes content, "ADMIN = new(0)"
      assert_includes content, "AUTHOR = new(1)"
      assert_includes content, "READER = new(2)"

      status_enum_path = File.join(dir, "user", "status_enum.rb")

      assert_path_exists status_enum_path

      status_content = File.read(status_enum_path)

      assert_includes status_content, "class UserStatusEnum < T::Enum"
      assert_includes status_content, "ACTIVE = new(0)"
      assert_includes status_content, "BANNED = new(1)"
    end
  end

  test "record types enum columns as enum class" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record_path = File.join(dir, "user", "record.rb")
      content = File.read(record_path)

      assert_includes content, "sig { returns(UserRoleEnum) }"
      assert_includes content, "sig { returns(UserStatusEnum) }"
    end
  end

  test "record generates predicate methods with prefix" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record_path = File.join(dir, "user", "record.rb")
      content = File.read(record_path)

      assert_includes content, "def role_admin?"
      assert_includes content, "def role_author?"
      assert_includes content, "def role_reader?"
      assert_includes content, "UserRoleEnum::ADMIN"
    end
  end

  test "record generates predicate methods with suffix" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record_path = File.join(dir, "user", "record.rb")
      content = File.read(record_path)

      assert_includes content, "def active_status?"
      assert_includes content, "def banned_status?"
      assert_includes content, "UserStatusEnum::ACTIVE"
    end
  end

  test "manifest includes enum files" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      manifest = File.read(File.join(dir, "manifest.rb"))

      assert_includes manifest, "user/role_enum"
      assert_includes manifest, "user/status_enum"
    end
  end

  test "cast expressions use enum deserialize" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record_path = File.join(dir, "user", "record.rb")
      content = File.read(record_path)

      assert_includes content, "UserRoleEnum.deserialize("
      assert_includes content, "UserStatusEnum.deserialize("
    end
  end

  test "HakumiORM.define_enums DSL works end-to-end" do
    HakumiORM.define_enums("users") do |e|
      e.enum :role, { admin: 0, author: 1 }, prefix: :role
    end

    result = HakumiORM.drain_enums!

    assert_equal 1, result["users"].length

    enum_def = result["users"].first

    assert_equal "role", enum_def.column_name
    assert_equal({ admin: 0, author: 1 }, enum_def.values)
    assert_equal :role, enum_def.prefix
  end

  test "EnumLoader loads from directory" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "users.rb"), <<~RUBY)
        HakumiORM.define_enums("users") do |e|
          e.enum :role, { admin: 0, author: 1, reader: 2 }, prefix: :role
        end
      RUBY

      result = HakumiORM::Codegen::EnumLoader.load(dir)

      assert_equal 1, result["users"].length
      assert_equal "role", result["users"].first.column_name
    end
  end

  test "rejects enum on incompatible column type (boolean)" do
    table = HakumiORM::Codegen::TableInfo.new("items")
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "INTEGER", udt_name: "INTEGER", nullable: true, default: nil, max_length: nil
    )
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "active", data_type: "BOOLEAN", udt_name: "BOOLEAN", nullable: false, default: nil, max_length: nil
    )
    table.primary_key = "id"

    bool_enum = HakumiORM::Codegen::EnumDefinition.new(
      column_name: "active", values: { yes: 0, no: 1 }
    )

    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Codegen::Generator.new(
        { "items" => table },
        HakumiORM::Codegen::GeneratorOptions.new(
          dialect: @dialect, output_dir: Dir.tmpdir, user_enums: { "items" => [bool_enum] }
        )
      )
    end

    assert_includes err.message, "not compatible"
    assert_includes err.message, "active"
  end

  test "rejects enum on incompatible column type (datetime)" do
    table = HakumiORM::Codegen::TableInfo.new("events")
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "INTEGER", udt_name: "INTEGER", nullable: true, default: nil, max_length: nil
    )
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "starts_at", data_type: "DATETIME", udt_name: "DATETIME", nullable: false, default: nil, max_length: nil
    )
    table.primary_key = "id"

    dt_enum = HakumiORM::Codegen::EnumDefinition.new(
      column_name: "starts_at", values: { morning: 0 }
    )

    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Codegen::Generator.new(
        { "events" => table },
        HakumiORM::Codegen::GeneratorOptions.new(
          dialect: @dialect, output_dir: Dir.tmpdir, user_enums: { "events" => [dt_enum] }
        )
      )
    end

    assert_includes err.message, "not compatible"
  end

  test "rejects enum on non-integer column (TEXT)" do
    table = HakumiORM::Codegen::TableInfo.new("posts")
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "INTEGER", udt_name: "INTEGER", nullable: true, default: nil, max_length: nil
    )
    table.columns << HakumiORM::Codegen::ColumnInfo.new(
      name: "kind", data_type: "TEXT", udt_name: "TEXT", nullable: false, default: nil, max_length: nil
    )
    table.primary_key = "id"

    wrong_enum = HakumiORM::Codegen::EnumDefinition.new(
      column_name: "kind", values: { draft: 0, published: 1 }
    )

    err = assert_raises(HakumiORM::Error) do
      HakumiORM::Codegen::Generator.new(
        { "posts" => table },
        HakumiORM::Codegen::GeneratorOptions.new(
          dialect: @dialect, output_dir: Dir.tmpdir, user_enums: { "posts" => [wrong_enum] }
        )
      )
    end

    assert_includes err.message, "not compatible"
    assert_includes err.message, "integer column"
  end

  test "EnumBuilder rejects non-integer values" do
    builder = HakumiORM::Codegen::EnumBuilder.new("users")

    err = assert_raises(HakumiORM::Error) do
      builder.enum(:role, { admin: "admin", author: "author" })
    end

    assert_includes err.message, "all values must be integers"
  end

  test "allows integer enum on integer column" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      content = File.read(File.join(dir, "user", "role_enum.rb"))

      assert_includes content, "ADMIN = new(0)"
    end
  end

  test "all user enums use IntBind in generated code" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      validated = File.read(File.join(dir, "user", "validated_record.rb"))

      assert_includes validated, "IntBind.new(T.cast(@record.role.serialize, Integer))"
      assert_includes validated, "IntBind.new(T.cast(@record.status.serialize, Integer))"
    end
  end

  test "all user enums use IntBind in insert_all" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "user", "record.rb"))

      assert_includes record, "T.cast(rec.role.serialize, Integer)"
      assert_includes record, "T.cast(rec.status.serialize, Integer)"
    end
  end

  test "all user enum deserialize uses to_i coercion" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, opts(dir))
      gen.generate!

      record = File.read(File.join(dir, "user", "record.rb"))

      assert_includes record, "deserialize(row[2].to_i)"
      assert_includes record, "deserialize(row[3].to_i)"
    end
  end

  private

  def opts(dir)
    HakumiORM::Codegen::GeneratorOptions.new(dialect: @dialect, output_dir: dir, user_enums: @user_enums)
  end
end
