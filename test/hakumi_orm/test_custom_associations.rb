# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestCustomAssociations < HakumiORM::TestCase
  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
  end

  # -- DSL -----------------------------------------------------------------

  test "associate DSL builds CustomAssociation structs" do
    HakumiORM.clear_associations!

    HakumiORM.associate("users") do |a|
      a.has_many "authored_articles", target: "articles", foreign_key: "author_email", primary_key: "email"
      a.has_one "latest_comment", target: "comments", foreign_key: "user_email", primary_key: "email", order_by: "created_at"
    end

    result = HakumiORM.drain_associations!

    assert_equal 2, result["users"].length

    hm = result["users"][0]

    assert_equal "authored_articles", hm.name
    assert_equal :has_many, hm.kind
    assert_nil hm.order_by

    ho = result["users"][1]

    assert_equal "latest_comment", ho.name
    assert_equal :has_one, ho.kind
    assert_equal "created_at", ho.order_by
  end

  test "drain_associations! clears the registry" do
    HakumiORM.clear_associations!

    HakumiORM.associate("users") do |a|
      a.has_many "posts", target: "posts", foreign_key: "user_id", primary_key: "id"
    end

    HakumiORM.drain_associations!
    result = HakumiORM.drain_associations!

    assert_empty result
  end

  test "AssociationLoader loads files from directory" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "users.rb"), <<~RUBY)
        HakumiORM.associate("users") do |a|
          a.has_many "articles", target: "articles", foreign_key: "author_email", primary_key: "email"
        end
      RUBY

      result = HakumiORM::Codegen::AssociationLoader.load(dir)

      assert_equal 1, result["users"].length
      assert_equal "articles", result["users"][0].name
    end
  end

  test "AssociationLoader returns empty hash for nonexistent directory" do
    result = HakumiORM::Codegen::AssociationLoader.load("/tmp/nonexistent_hakumi_#{Process.pid}")

    assert_empty result
  end

  # -- Validation ----------------------------------------------------------

  test "rejects invalid kind" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("things", target: "articles", foreign_key: "author_email",
                                             primary_key: "email", kind: :belongs_to)]
               })
    end

    assert_includes err.message, "has_many"
    assert_includes err.message, "has_one"
  end

  test "rejects invalid name (not a valid Ruby identifier)" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("123bad", target: "articles", foreign_key: "author_email", primary_key: "email")]
               })
    end

    assert_includes err.message, "123bad"
  end

  test "rejects missing target_table" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("things", target: "nonexistent", foreign_key: "author_email", primary_key: "email")]
               })
    end

    assert_includes err.message, "nonexistent"
  end

  test "rejects missing source table" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "ghosts" => [assoc("things", target: "articles", foreign_key: "author_email", primary_key: "email")]
               })
    end

    assert_includes err.message, "ghosts"
  end

  test "rejects missing foreign_key column on target table" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("things", target: "articles", foreign_key: "nonexistent_col", primary_key: "email")]
               })
    end

    assert_includes err.message, "nonexistent_col"
    assert_includes err.message, "articles"
  end

  test "rejects missing primary_key column on source table" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("things", target: "articles", foreign_key: "author_email", primary_key: "nonexistent_col")]
               })
    end

    assert_includes err.message, "nonexistent_col"
    assert_includes err.message, "users"
  end

  test "rejects nullable primary_key on source table" do
    users = make_table("users", columns: [pk_col("users"), str_col("name"),
                                          col("nickname", type: "character varying",
                                                          udt: "varchar", nullable: true)])
    articles = make_table("articles", columns: [pk_col("articles"), str_col("author_nick")])
    tables = { "users" => users, "articles" => articles }

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("articles_by_nick", target: "articles",
                                                       foreign_key: "author_nick", primary_key: "nickname")]
               })
    end

    assert_includes err.message, "nullable"
    assert_includes err.message, "nickname"
  end

  test "rejects type mismatch between source and target columns" do
    users = make_table("users", columns: [pk_col("users"), str_col("email")])
    articles = make_table("articles", columns: [pk_col("articles"), col("author_ref")])
    tables = { "users" => users, "articles" => articles }

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("things", target: "articles", foreign_key: "author_ref", primary_key: "email")]
               })
    end

    assert_includes err.message, "type"
    assert_includes err.message, "email"
    assert_includes err.message, "author_ref"
  end

  test "rejects name collision with existing FK association" do
    users = make_table("users", columns: [pk_col("users"), str_col("email")])
    posts = make_table("posts",
                       columns: [pk_col("posts"), fk_col("user_id"), str_col("author_email")],
                       fks: [fk("user_id", "users")])
    tables = { "users" => users, "posts" => posts }

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("posts", target: "posts", foreign_key: "author_email", primary_key: "email")]
               })
    end

    assert_includes err.message, "posts"
    assert_includes err.message, "collision"
  end

  test "rejects name collision with column" do
    tables = build_users_articles_tables

    err = assert_raises(HakumiORM::Error) do
      generate(tables, custom_associations: {
                 "users" => [assoc("email", target: "articles", foreign_key: "author_email", primary_key: "email")]
               })
    end

    assert_includes err.message, "email"
    assert_includes err.message, "column"
  end

  # -- Generation ----------------------------------------------------------

  test "has_many custom association generates accessor and preload" do
    tables = build_users_articles_tables

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: {
                 "users" => [assoc("authored_articles", target: "articles",
                                                        foreign_key: "author_email", primary_key: "email")]
               })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def authored_articles"
      assert_includes record, "_preloaded_authored_articles"
      assert_includes record, "ArticleSchema::AUTHOR_EMAIL"
      assert_includes record, "def self.preload_authored_articles"
      assert_includes record, "in_list"

      relation = File.read(File.join(dir, "user/relation.rb"))

      assert_includes relation, "when :authored_articles"
    end
  end

  test "has_one custom association generates accessor with first" do
    tables = build_users_articles_tables

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: {
                 "users" => [assoc("latest_article", target: "articles",
                                                     foreign_key: "author_email", primary_key: "email", kind: :has_one)]
               })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def latest_article"
      assert_includes record, "_preloaded_latest_article"
      assert_includes record, ".first"
    end
  end

  test "has_one with order_by includes ORDER BY in query" do
    tables = build_users_articles_tables

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: {
                 "users" => [assoc("latest_article", target: "articles",
                                                     foreign_key: "author_email", primary_key: "email",
                                                     kind: :has_one, order_by: "id")]
               })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "order(ArticleSchema::ID.desc)"
    end
  end

  test "custom associations coexist with FK associations" do
    users = make_table("users", columns: [pk_col("users"), str_col("name"), str_col("email")])
    posts = make_table("posts",
                       columns: [pk_col("posts"), fk_col("user_id"), str_col("title")],
                       fks: [fk("user_id", "users")])
    articles = make_table("articles", columns: [pk_col("articles"), str_col("author_email"), str_col("title")])
    tables = { "users" => users, "posts" => posts, "articles" => articles }

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: {
                 "users" => [assoc("authored_articles", target: "articles",
                                                        foreign_key: "author_email", primary_key: "email")]
               })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def posts"
      assert_includes record, "def authored_articles"

      relation = File.read(File.join(dir, "user/relation.rb"))

      assert_includes relation, "when :posts"
      assert_includes relation, "when :authored_articles"
    end
  end

  test "self-join custom association generates correctly" do
    users = make_table("users",
                       columns: [pk_col("users"), str_col("name"), str_col("email"), str_col("mentor_email")])
    tables = { "users" => users }

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: {
                 "users" => [assoc("mentees", target: "users", foreign_key: "mentor_email", primary_key: "email")]
               })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def mentees"
      assert_includes record, "UserSchema::MENTOR_EMAIL"
    end
  end

  # -- Scoping -------------------------------------------------------------

  test "associate DSL accepts scope parameter" do
    HakumiORM.clear_associations!

    HakumiORM.associate("users") do |a|
      a.has_many "published_articles", target: "articles", foreign_key: "author_email",
                                       primary_key: "email", scope: "ArticleSchema::PUBLISHED.eq(true)"
    end

    result = HakumiORM.drain_associations!
    hm = result["users"][0]

    assert_equal "ArticleSchema::PUBLISHED.eq(true)", hm.scope
  end

  test "scoped has_many generates .where(scope) in accessor" do
    tables = build_users_articles_tables
    tables["articles"].columns << col("published", type: "boolean", udt: "bool")

    scoped_assoc = HakumiORM::Codegen::CustomAssociation.new(
      name: "published_articles", target_table: "articles", foreign_key: "author_email",
      primary_key: "email", kind: :has_many, scope: "ArticleSchema::PUBLISHED.eq(true)"
    )

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: { "users" => [scoped_assoc] })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def published_articles"
      assert_includes record, ".where(ArticleSchema::PUBLISHED.eq(true))"
    end
  end

  test "scoped has_many generates .where(scope) in preloader" do
    tables = build_users_articles_tables
    tables["articles"].columns << col("published", type: "boolean", udt: "bool")

    scoped_assoc = HakumiORM::Codegen::CustomAssociation.new(
      name: "published_articles", target_table: "articles", foreign_key: "author_email",
      primary_key: "email", kind: :has_many, scope: "ArticleSchema::PUBLISHED.eq(true)"
    )

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: { "users" => [scoped_assoc] })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def self.preload_published_articles"
      assert_match(/in_list.*\.where\(ArticleSchema::PUBLISHED\.eq\(true\)\)\.to_a/, record)
    end
  end

  test "scoped has_one generates .where(scope) in accessor" do
    tables = build_users_articles_tables

    scoped_assoc = HakumiORM::Codegen::CustomAssociation.new(
      name: "latest_published", target_table: "articles", foreign_key: "author_email",
      primary_key: "email", kind: :has_one, scope: "ArticleSchema::PUBLISHED.eq(true)"
    )

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: { "users" => [scoped_assoc] })

      record = File.read(File.join(dir, "user/record.rb"))

      assert_includes record, "def latest_published"
      assert_includes record, ".where(ArticleSchema::PUBLISHED.eq(true)).first"
    end
  end

  test "unscoped associations do not include extra .where chain" do
    tables = build_users_articles_tables

    assocs = { "users" => [assoc("articles", target: "articles", foreign_key: "author_email", primary_key: "email")] }

    Dir.mktmpdir do |dir|
      generate(tables, output_dir: dir, custom_associations: assocs)

      record = File.read(File.join(dir, "user/record.rb"))

      refute_match(/\.eq\(@email\)\)\.where\(/, record)
    end
  end

  # -- Helpers -------------------------------------------------------------

  private

  def assoc(name, target:, foreign_key:, primary_key:, kind: :has_many, order_by: nil)
    HakumiORM::Codegen::CustomAssociation.new(
      name: name, target_table: target, foreign_key: foreign_key,
      primary_key: primary_key, kind: kind, order_by: order_by
    )
  end

  def generate(tables, output_dir: nil, **overrides)
    dir = output_dir || Dir.mktmpdir
    gen = HakumiORM::Codegen::Generator.new(tables, opts(dir, **overrides))
    gen.generate!
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

  def build_users_articles_tables
    users = make_table("users", columns: [pk_col("users"), str_col("name"), str_col("email")])
    articles = make_table("articles", columns: [pk_col("articles"), str_col("author_email"), str_col("title")])
    { "users" => users, "articles" => articles }
  end
end
