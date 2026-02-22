# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestModelAnnotator < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
  end

  test "annotates model file with schema and FK associations" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      tables = build_users_posts_tables
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "# == Schema Information =="
      assert_includes code, "# == End Schema Information =="
      assert_includes code, "# Table: users"
      assert_includes code, "# Primary key: id"
      assert_includes code, "#   id"
      assert_includes code, "#   name"
      assert_includes code, "has_many"
      assert_includes code, ":posts"
    end
  end

  test "annotation includes custom associations" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      tables = build_users_articles_tables
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir, custom_associations: {
                                                             "users" => [custom_assoc("authored_articles", target: "articles",
                                                                                                           foreign_key: "author_email", primary_key: "email")]
                                                           }))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "authored_articles"
      assert_includes code, "custom"
    end
  end

  test "annotation replaces existing block without touching user code" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")
      FileUtils.mkdir_p(models_dir)

      File.write(File.join(models_dir, "user.rb"), <<~RUBY)
        # typed: strict
        # frozen_string_literal: true

        # == Schema Information ==
        # old content
        # == End Schema Information ==

        class User < UserRecord
          def custom_method
            "hello"
          end
        end
      RUBY

      tables = build_simple_users_table
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "# Table: users"
      refute_includes code, "old content"
      assert_includes code, "custom_method"
      assert_includes code, '"hello"'
    end
  end

  test "annotation is prepended if no markers exist in legacy file" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")
      FileUtils.mkdir_p(models_dir)

      File.write(File.join(models_dir, "user.rb"), <<~RUBY)
        # typed: strict
        # frozen_string_literal: true

        class User < UserRecord
          def greet
            "hi"
          end
        end
      RUBY

      tables = build_simple_users_table
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))

      assert_includes code, "# == Schema Information =="
      assert_includes code, "# Table: users"
      assert_includes code, "def greet"

      lines = code.lines
      marker_idx = lines.index { |l| l.include?("# == Schema Information ==") }
      class_idx = lines.index { |l| l.include?("class User") }

      assert_operator marker_idx, :<, class_idx
    end
  end

  test "columns are listed in alphabetical order" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      tables = build_users_articles_tables
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      code = File.read(File.join(models_dir, "user.rb"))
      lines = code.lines.grep(/^#\s+\w+\s+(integer|string|boolean)/)
      col_names = lines.map { |l| l.strip.split(/\s+/)[1] }

      assert_equal col_names.sort, col_names
    end
  end

  private

  def custom_assoc(name, target:, foreign_key:, primary_key:, kind: :has_many, order_by: nil)
    HakumiORM::Codegen::CustomAssociation.new(
      name: name, target_table: target, foreign_key: foreign_key,
      primary_key: primary_key, kind: kind, order_by: order_by
    )
  end

  def opts(dir, **overrides)
    HakumiORM::Codegen::GeneratorOptions.new(dialect: @dialect, output_dir: dir, **overrides)
  end

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

  def build_simple_users_table
    users = make_table("users", columns: [pk_col("users"), str_col("name"), str_col("email")])
    { "users" => users }
  end

  def build_users_posts_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name")])
    posts = make_table("posts",
                       columns: [pk_col("posts"), fk_col("user_id"), str_col("title")],
                       fks: [fk("user_id", "users")])
    { "users" => users, "posts" => posts }
  end

  def build_users_articles_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name"), str_col("email")])
    articles = make_table("articles",
                          columns: [pk_col("articles"), str_col("author_email"), str_col("title")])
    { "users" => users, "articles" => articles }
  end
end
