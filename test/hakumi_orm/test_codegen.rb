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

  test "generates singular folder with schema, record, new_record, relation" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      assert_path_exists File.join(dir, "user/schema.rb"), "Missing user/schema.rb"
      assert_path_exists File.join(dir, "user/record.rb"), "Missing user/record.rb"
      assert_path_exists File.join(dir, "user/new_record.rb"), "Missing user/new_record.rb"
      assert_path_exists File.join(dir, "user/relation.rb"), "Missing user/relation.rb"
      assert_path_exists File.join(dir, "manifest.rb"), "Missing manifest.rb"
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

  test "new_record has insertable columns and save!" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/new_record.rb"))

      assert_includes code, "typed: strict"
      assert_includes code, "class UserRecord"
      assert_includes code, "class New"
      assert_includes code, "attr_reader :name"
      assert_includes code, "attr_reader :email"
      assert_includes code, "attr_reader :age"
      assert_includes code, "attr_reader :active"
      refute_includes code, "attr_reader :id"
      assert_includes code, "def save!"
      assert_includes code, "SQL_INSERT"
      assert_includes code, "RETURNING"
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
    end
  end

  test "generated code contains zero T.untyped, T.unsafe, and T.must" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      %w[user/schema.rb user/record.rb user/new_record.rb user/relation.rb].each do |file|
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

  test "manifest requires files in singular folder structure" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "manifest.rb"))

      assert_includes code, 'require_relative "user/schema"'
      assert_includes code, 'require_relative "user/record"'
      assert_includes code, 'require_relative "user/new_record"'
      assert_includes code, 'require_relative "user/relation"'
    end
  end

  test "insert SQL in new_record skips serial columns and uses RETURNING with all columns" do
    Dir.mktmpdir do |dir|
      gen = HakumiORM::Codegen::Generator.new(@tables, dialect: @dialect, output_dir: dir)
      gen.generate!

      code = File.read(File.join(dir, "user/new_record.rb"))

      assert_includes code, "SQL_INSERT"
      refute_includes code, '"id") VALUES'
      assert_includes code, "RETURNING"
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
