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
end
