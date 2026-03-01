# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/codegen"
require "tmpdir"

class TestTableHooks < HakumiORM::TestCase
  TableHook = HakumiORM::Codegen::TableHook
  Generator = HakumiORM::Codegen::Generator
  GeneratorOptions = HakumiORM::Codegen::GeneratorOptions
  ModelAnnotator = HakumiORM::Codegen::ModelAnnotator

  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new

    col_id = HakumiORM::Codegen::ColumnInfo.new(
      name: "id", data_type: "integer", udt_name: "int4",
      nullable: false, default: nil, max_length: nil
    )
    col_name = HakumiORM::Codegen::ColumnInfo.new(
      name: "name", data_type: "character varying", udt_name: "varchar",
      nullable: false, default: nil, max_length: 255
    )

    users_table = HakumiORM::Codegen::TableInfo.new("users")
    users_table.columns << col_id << col_name
    users_table.primary_key = "id"

    posts_table = HakumiORM::Codegen::TableInfo.new("posts")
    posts_table.columns << col_id << col_name
    posts_table.primary_key = "id"

    @tables = { "users" => users_table, "posts" => posts_table }
  end

  test "TableHook defaults to skip: false and empty annotation_lines" do
    hook = TableHook.new
    refute hook.skip
    assert_empty hook.annotation_lines
  end

  test "TableHook skip: true marks table as skipped" do
    hook = TableHook.new(skip: true)
    assert hook.skip
  end

  test "TableHook annotation_lines stores provided lines" do
    hook = TableHook.new(annotation_lines: ["legacy table", "do not add columns"])
    assert_equal ["legacy table", "do not add columns"], hook.annotation_lines
  end

  test "on_table registers a hook retrievable via drain_table_hooks!" do
    HakumiORM.on_table("users", skip: true)
    hooks = HakumiORM.drain_table_hooks!

    assert hooks.key?("users")
    assert hooks["users"].skip
  end

  test "clear_table_hooks! empties the registry" do
    HakumiORM.on_table("users", skip: true)
    HakumiORM.clear_table_hooks!
    hooks = HakumiORM.drain_table_hooks!

    assert_empty hooks
  end

  test "drain_table_hooks! returns hooks and clears registry" do
    HakumiORM.on_table("users", annotation_lines: ["line1"])
    first = HakumiORM.drain_table_hooks!
    second = HakumiORM.drain_table_hooks!

    assert first.key?("users")
    assert_empty second
  end

  test "multiple on_table calls register independent hooks" do
    HakumiORM.on_table("users", skip: true)
    HakumiORM.on_table("posts", annotation_lines: ["archived"])
    hooks = HakumiORM.drain_table_hooks!

    assert hooks["users"].skip
    refute hooks["posts"].skip
    assert_equal ["archived"], hooks["posts"].annotation_lines
  end

  test "skip: true prevents generating any files for that table" do
    hooks = { "users" => TableHook.new(skip: true) }

    Dir.mktmpdir do |dir|
      gen = Generator.new(@tables, opts(dir, table_hooks: hooks))
      gen.generate!

      refute File.exist?(File.join(dir, "user")), "user/ directory should not exist"
      assert File.exist?(File.join(dir, "post")), "post/ directory should exist"
    end
  end

  test "skip: false generates files normally" do
    hooks = { "users" => TableHook.new(skip: false) }

    Dir.mktmpdir do |dir|
      gen = Generator.new(@tables, opts(dir, table_hooks: hooks))
      gen.generate!

      assert File.exist?(File.join(dir, "user", "schema.rb"))
    end
  end

  test "table with no hook is generated normally" do
    Dir.mktmpdir do |dir|
      gen = Generator.new(@tables, opts(dir))
      gen.generate!

      assert File.exist?(File.join(dir, "user", "schema.rb"))
      assert File.exist?(File.join(dir, "post", "schema.rb"))
    end
  end

  test "skipping one table does not affect other tables" do
    hooks = { "posts" => TableHook.new(skip: true) }

    Dir.mktmpdir do |dir|
      gen = Generator.new(@tables, opts(dir, table_hooks: hooks))
      gen.generate!

      assert File.exist?(File.join(dir, "user", "schema.rb"))
      refute File.exist?(File.join(dir, "post"))
    end
  end

  test "annotation_lines are injected into the schema annotation block" do
    hook = TableHook.new(annotation_lines: ["legacy table", "do not add columns"])
    table = @tables["users"]

    ctx = ModelAnnotator::Context.new(
      table: table,
      dialect: @dialect,
      associations: ModelAnnotator::AssociationSets.new,
      extra_lines: hook.annotation_lines
    )

    annotation = ModelAnnotator.build_annotation(ctx)

    assert_includes annotation, "# legacy table"
    assert_includes annotation, "# do not add columns"
  end

  test "annotation without extra_lines has no injected lines" do
    table = @tables["users"]

    ctx = ModelAnnotator::Context.new(
      table: table,
      dialect: @dialect,
      associations: ModelAnnotator::AssociationSets.new
    )

    annotation = ModelAnnotator.build_annotation(ctx)

    refute_includes annotation, "# legacy table"
  end

  test "extra_lines appear after associations section in annotation" do
    table = @tables["users"]

    ctx = ModelAnnotator::Context.new(
      table: table,
      dialect: @dialect,
      associations: ModelAnnotator::AssociationSets.new,
      extra_lines: ["note: custom line"]
    )

    annotation = ModelAnnotator.build_annotation(ctx)
    marker_end_pos = annotation.index("# == End Schema Information ==")
    extra_line_pos = annotation.index("# note: custom line")

    assert extra_line_pos, "Extra line not found in annotation"
    assert extra_line_pos < marker_end_pos, "Extra line should appear before closing marker"
  end

  private

  def opts(dir, **overrides)
    GeneratorOptions.new(dialect: @dialect, output_dir: dir, **overrides)
  end
end
