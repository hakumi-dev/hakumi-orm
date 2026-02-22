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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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

  test "record has update! with SQL_UPDATE_BY_PK and RETURNING" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "SQL_UPDATE_BY_PK"
      assert_includes code, 'UPDATE "users" SET'
      assert_includes code, "RETURNING"
      assert_includes code, "def update!"
      assert_includes code, "Contract.on_update"
      assert_includes code, "Contract.on_all"
      assert_includes code, "Contract.on_persist"
    end
  end

  test "base_contract has on_update hook" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/base_contract.rb"))

      assert_includes code, "def self.on_update"
      assert_includes code, "UserRecord::Checkable"
    end
  end

  test "record has delete! with SQL_DELETE_BY_PK" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "def to_h"
      assert_includes code, "T::Hash[Symbol,"
      refute_includes code, "T.untyped"
    end
  end

  test "record has find_by and exists? class methods" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      assert_includes code, "def self.find_by"
      assert_includes code, "def self.exists?"
    end
  end

  test "record has typed attributes, keyword args, and hydration" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      assert_includes code, "def initialize(id:, name:, email:, age:, active:)"
      assert_includes code, "def self.from_result"
      assert_includes code, "def self.where"
      assert_includes code, "def self.all"
      assert_includes code, "def self.find"
      assert_includes code, "def self.build"
    end
  end

  test "new_record has insertable columns, validate!, and includes Checkable" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: dir, module_name: "App"
      )
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "manifest.rb"))

      %w[checkable schema record new_record validated_record base_contract variant_base relation].each do |name|
        assert_includes code, "require_relative \"user/#{name}\""
      end
    end
  end

  test "variant_base delegates all columns including pk" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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

      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: gen_dir, models_dir: models_dir
      )
      gen.generate!

      model_path = File.join(models_dir, "user.rb")

      assert_path_exists model_path, "Missing models/user.rb"

      code = File.read(model_path)

      assert_includes code, "class User < UserRecord"
      assert_includes code, "typed: strict"
    end
  end

  test "models_dir does not overwrite existing model files" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")
      FileUtils.mkdir_p(models_dir)

      custom_code = "class User < UserRecord\n  def custom_method; end\nend\n"
      File.write(File.join(models_dir, "user.rb"), custom_code)

      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: gen_dir, models_dir: models_dir
      )
      gen.generate!

      assert_equal custom_code, File.read(File.join(models_dir, "user.rb"))
    end
  end

  test "checkable generates an interface module with abstract field readers" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/base_contract.rb"))

      assert_includes code, "class UserRecord::BaseContract"
      assert_includes code, "overridable"
      assert_includes code, "def self.on_all"
      assert_includes code, "def self.on_create"
      assert_includes code, "def self.on_persist"
      assert_includes code, "UserRecord::Checkable"
      assert_includes code, "UserRecord::New"
    end
  end

  test "contracts_dir generates contract stubs extending BaseContract" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      contracts_dir = File.join(dir, "contracts")

      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: gen_dir, contracts_dir: contracts_dir
      )
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
      gen = HakumiORM::Codegen::Generator.new({ "posts" => table }, dialect: @dialect, output_dir: dir)
      gen.generate!

      validated_code = File.read(File.join(dir, "post/validated_record.rb"))

      assert_includes validated_code, "TimeBind.new(::Time.now)", "save! should auto-set created_at/updated_at"

      record_code = File.read(File.join(dir, "post/record.rb"))

      assert_includes record_code, "SQL_UPDATE_BY_PK"
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
      gen = HakumiORM::Codegen::Generator.new({ "logs" => table }, dialect: @dialect, output_dir: dir)
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

      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: gen_dir, contracts_dir: contracts_dir
      )
      gen.generate!

      assert_equal custom_code, File.read(File.join(contracts_dir, "user_contract.rb"))
    end
  end

  test "models_dir with module_name wraps model in module" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      gen = HakumiORM::Codegen::Generator.new(
        @tables, dialect: @dialect, output_dir: gen_dir, models_dir: models_dir, module_name: "App"
      )
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "module App"
      assert_includes code, "class App::User < App::UserRecord"
    end
  end

  test "has_many generates association method and preload" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def posts"
      assert_includes user_code, "PostRelation"
      assert_includes user_code, "def self.preload_posts"
    end
  end

  test "has_one generates singular accessor when FK has unique constraint" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "related ? [related] : []"
    end
  end

  test "belongs_to generates accessor and preload" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      rel_code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes rel_code, "when :profile"
      assert_includes rel_code, "preload_profile"
    end
  end

  test "relation run_preloads accepts PreloadNode and dispatches nested" do
    tables = build_users_and_posts_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      rel_code = File.read(File.join(dir, "user/relation.rb"))

      assert_includes rel_code, "PreloadNode"
      assert_includes rel_code, "node.name"
      assert_includes rel_code, "node.children"
      assert_includes rel_code, "PostRelation.new.run_preloads"
    end
  end

  test "has_many through join table generates subquery method" do
    tables = build_users_roles_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "def delete!(adapter:"
      refute_includes user_code, "dependent:"
    end
  end

  test "delete! with has_one generates destroy with safe navigation" do
    tables = build_users_and_profile_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      user_code = File.read(File.join(dir, "user/record.rb"))

      assert_includes user_code, "SQL_DELETE_PROFILE"
      assert_includes user_code, "profile(adapter: adapter)&.delete!"
    end
  end

  test "has_many through chain generates subquery method" do
    tables = build_users_posts_comments_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      role_code = File.read(File.join(dir, "role/record.rb"))

      assert_includes role_code, "def users"
      assert_includes role_code, "SubqueryExpr"
      assert_includes role_code, "UsersRoleSchema::ROLE_ID"
      assert_includes role_code, "UsersRoleSchema::USER_ID"
      assert_includes role_code, "UserSchema::ID"
    end
  end

  test "has_one through generates singular method with first" do
    tables = build_users_profiles_avatars_tables
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "product/record.rb"))

      assert_match(/def update!\(name:/, code)
      refute_match(/def update!.*lock_version:/, code)
    end
  end

  test "tables without lock_version do not use StaleObjectError" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      refute_includes code, "StaleObjectError"
      refute_includes code, "lock_version"
    end
  end

  test "json column generates JsonField and Cast.to_json" do
    tables = build_table_with_json
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      schema = File.read(File.join(dir, "event/schema.rb"))
      record = File.read(File.join(dir, "event/record.rb"))

      assert_includes schema, "::HakumiORM::JsonField"
      assert_includes record, "::HakumiORM::Json"
      assert_includes record, "Cast.to_json"
    end
  end

  test "schema escapes double quotes in postgresql qualified names" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/schema.rb"))

      assert_includes code, '\"users\".\"name\"'
      assert_includes code, '\"users\".\"email\"'
    end
  end

  test "schema uses backticks for mysql qualified names without extra escaping" do
    dialect = HakumiORM::Dialect::Mysql.new
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: dialect, output_dir: dir)
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
      def qualified_name(tbl, col)
        "\"#{tbl}\\\".\"#{col}\""
      end
    end.new

    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new({ "weird" => table }, dialect: dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "weird/schema.rb"))

      assert_includes code, '\\\\\"'
    end
  end

  test "as_json generates hash with string keys and JSON-safe values" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new({ "events" => table }, dialect: @dialect, output_dir: dir)
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
      gen = HakumiORM::Codegen::Generator.new({ "items" => table }, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "item/record.rb"))

      assert_includes code, '@price.to_s("F")'
      assert_includes code, "@meta&.raw_json"
    end
  end

  test "as_json has zero T.untyped, T.unsafe, T.must" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/record.rb"))

      refute_includes code, "T.untyped"
      refute_includes code, "T.unsafe"
      refute_includes code, "T.must"
    end
  end

  test "variant_base delegates as_json and to_h" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/variant_base.rb"))

      assert_includes code, "def to_h = @record.to_h"
      assert_includes code, "def as_json(only: nil, except: nil) = @record.as_json(only: only, except: except)"
    end
  end

  test "uuid column generates StrField" do
    tables = build_table_with_uuid
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      schema = File.read(File.join(dir, "token/schema.rb"))
      record = File.read(File.join(dir, "token/record.rb"))

      assert_includes schema, "::HakumiORM::StrField"
      assert_includes record, "returns(String)"
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
end
