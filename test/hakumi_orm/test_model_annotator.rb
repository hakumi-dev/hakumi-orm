# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestModelAnnotator < HakumiORM::TestCase
  Annotator = HakumiORM::Codegen::ModelAnnotator
  Context = Annotator::Context

  def setup
    @dialect = HakumiORM::Dialect::Postgresql.new
  end

  test "header includes table name" do
    ctx = build_ctx(table: simple_users_table)
    block = Annotator.build_annotation(ctx)

    assert_includes block, "# Table name: users"
  end

  test "header includes primary key with type" do
    ctx = build_ctx(table: simple_users_table)
    block = Annotator.build_annotation(ctx)

    assert_includes block, "# Primary key: id (integer, not null)"
  end

  test "header omits primary key line when table has no PK" do
    table = make_table("logs", columns: [str_col("message")], pk: nil)
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    assert_includes block, "# Table name: logs"
    refute_includes block, "Primary key"
  end

  test "columns are formatted with sprintf pattern: name:type attrs" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         str_col("name"),
                         str_col("email")
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    assert_match(/^# email\s+:string\s+not null$/, block)
    assert_match(/^# id\s+:integer\s+.*primary key$/, block)
    assert_match(/^# name\s+:string\s+not null$/, block)
  end

  test "column names are right-padded to align colons" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         str_col("a"),
                         str_col("long_column_name")
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)
    col_lines = block.lines.grep(/^# \w+\s+:/)

    colon_positions = col_lines.map { |l| l.index(":") }

    assert_equal 1, colon_positions.uniq.length, "All colons should be at the same position"
  end

  test "type labels are right-padded to BARE_TYPE_ALLOWANCE (16)" do
    table = make_table("items", columns: [
                         col("id", default: "nextval('items_id_seq'::regclass)"),
                         col("count", nullable: true)
                       ])
    table.primary_key = "id"
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    id_line = block.lines.find { |l| l.include?("# id") && l.include?(":integer") }

    refute_nil id_line

    after_colon = id_line.split(":", 2).last
    type_part = after_colon.split.first

    assert_equal "integer", type_part
  end

  test "nullable column omits not null attribute" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         col("bio", type: "text", udt: "text", nullable: true)
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)
    bio_line = block.lines.find { |l| l.include?("# bio") }

    refute_nil bio_line
    refute_includes bio_line, "not null"
  end

  test "column with default shows default(value)" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         col("active", type: "boolean", udt: "bool", default: "true")
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    assert_match(/default\(true\)/, block)
  end

  test "primary key column shows primary key attribute" do
    table = make_table("users", columns: [pk_col("users"), str_col("name")])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)
    id_line = block.lines.find { |l| l.include?("# id") }

    assert_includes id_line, "primary key"
  end

  test "multiple attributes are comma-separated" do
    table = make_table("users", columns: [pk_col("users")])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)
    id_line = block.lines.find { |l| l.include?("# id") }

    assert_match(/not null, default\(.*\), primary key/, id_line)
  end

  test "no line has trailing whitespace" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         str_col("name"),
                         col("bio", type: "text", udt: "text", nullable: true),
                         col("age", nullable: true)
                       ])
    ctx = build_ctx(table: table,
                    has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }],
                    has_many_through: [{ method_name: "tags", join_table: "" }])
    block = Annotator.build_annotation(ctx)

    block.lines.each_with_index do |line, idx|
      refute_match(/[ \t]+$/, line.chomp, "Line #{idx + 1} has trailing whitespace: #{line.inspect}")
    end
  end

  test "enum column shows enum(ClassName) type" do
    table = make_table("users", columns: [
                         pk_col("users"),
                         HakumiORM::Codegen::ColumnInfo.new(
                           name: "role", data_type: "USER-DEFINED", udt_name: "users_role",
                           nullable: false, default: nil, max_length: nil, enum_values: %w[admin author reader]
                         )
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    assert_match(/role\s+:enum\(UsersRoleEnum\)/, block)
  end

  test "enum section is omitted when no predicates" do
    ctx = build_ctx(table: simple_users_table, enum_predicates: [])
    block = Annotator.build_annotation(ctx)

    refute_includes block, "Enums:"
  end

  test "enum section lists column class and values" do
    predicates = [
      { column: "role", enum_class: "UsersRoleEnum", const: "ADMIN", method_name: "role_admin?" },
      { column: "role", enum_class: "UsersRoleEnum", const: "READER", method_name: "role_reader?" }
    ]
    ctx = build_ctx(table: simple_users_table, enum_predicates: predicates)
    block = Annotator.build_annotation(ctx)

    assert_includes block, "# Enums:"
    assert_match(/role\s*:UsersRoleEnum\s+\[admin, reader\]/, block)
    assert_includes block, "predicates: role_admin?, role_reader?"
  end

  test "enum section with multiple columns groups correctly" do
    predicates = [
      { column: "role", enum_class: "UsersRoleEnum", const: "ADMIN", method_name: "role_admin?" },
      { column: "status", enum_class: "UsersStatusEnum", const: "ACTIVE", method_name: "active_status?" }
    ]
    ctx = build_ctx(table: simple_users_table, enum_predicates: predicates)
    block = Annotator.build_annotation(ctx)

    assert_match(/role\s+:UsersRoleEnum/, block)
    assert_match(/status\s*:UsersStatusEnum/, block)
  end

  test "association section is omitted when empty" do
    ctx = build_ctx(table: simple_users_table)
    block = Annotator.build_annotation(ctx)

    refute_includes block, "Associations:"
  end

  test "has_many association is listed with FK detail" do
    ctx = build_ctx(
      table: simple_users_table,
      has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)

    assert_includes block, "# Associations:"
    assert_match(/has_many\s*:posts\s+FK: posts\.user_id -> users\.id/, block)
  end

  test "has_one association is listed with FK detail" do
    ctx = build_ctx(
      table: simple_users_table,
      has_one: [{ method_name: "profile", fk_attr: "user_id", pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)

    assert_match(/has_one\s*:profile\s+FK: profile\.user_id -> users\.id/, block)
  end

  test "belongs_to association is listed with FK detail" do
    table = make_table("posts", columns: [pk_col("posts"), fk_col("user_id"), str_col("title")],
                                fks: [fk("user_id", "users")])
    ctx = build_ctx(
      table: table,
      belongs_to: [{ method_name: "user", fk_attr: "user_id", target_pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)

    assert_match(/belongs_to\s*:user\s+FK: posts\.user_id -> user\.id/, block)
  end

  test "has_many through association shows through detail" do
    ctx = build_ctx(
      table: simple_users_table,
      has_many_through: [{ method_name: "tags", join_table: "taggings" }]
    )
    block = Annotator.build_annotation(ctx)

    assert_match(/has_many\s*:tags\s+through: taggings/, block)
  end

  test "custom association shows custom detail" do
    ctx = build_ctx(
      table: simple_users_table,
      custom_has_many: [{ method_name: "articles", fk_attr: "author_email", pk_attr: "email", target_table: "articles" }]
    )
    block = Annotator.build_annotation(ctx)

    assert_match(/has_many\s*:articles\s+custom: articles\.author_email -> users\.email/, block)
  end

  test "mixed associations are all listed" do
    ctx = build_ctx(
      table: simple_users_table,
      has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }],
      has_one: [{ method_name: "profile", fk_attr: "user_id", pk_attr: "id" }],
      has_many_through: [{ method_name: "comments", join_table: "posts" }]
    )
    block = Annotator.build_annotation(ctx)
    lines = block.lines

    assert(lines.any? { |l| l.include?("has_many") && l.include?(":posts") })
    assert(lines.any? { |l| l.include?("has_one") && l.include?(":profile") })
    assert(lines.any? { |l| l.include?("has_many") && l.include?(":comments") && l.include?("through:") })
  end

  test "association kinds are right-padded to align names" do
    ctx = build_ctx(
      table: simple_users_table,
      has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }],
      belongs_to: [{ method_name: "company", fk_attr: "company_id", target_pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)
    assoc_lines = block.lines.grep(/^# (has_many|has_one|belongs_to)\s/)

    colon_positions = assoc_lines.map { |l| l.index(":") }

    assert_equal 1, colon_positions.uniq.length, "All association name colons should be at the same position"
  end

  test "insert_annotation replaces existing annotation block" do
    original = <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      # == Schema Information ==
      # old content
      # == End Schema Information ==

      class User < UserRecord
        def custom_method; end
      end
    RUBY

    new_annotation = "# == Schema Information ==\n# new content\n# == End Schema Information =="
    result = Annotator.insert_annotation(original, new_annotation)

    assert_includes result, "new content"
    refute_includes result, "old content"
    assert_includes result, "custom_method"
  end

  test "insert_annotation inserts before class when no markers exist" do
    original = <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      class User < UserRecord
        def greet; end
      end
    RUBY

    annotation = "# == Schema Information ==\n# content\n# == End Schema Information =="
    result = Annotator.insert_annotation(original, annotation)
    lines = result.lines

    marker_idx = lines.index { |l| l.include?("# == Schema Information ==") }
    class_idx = lines.index { |l| l.include?("class User") }

    refute_nil marker_idx
    refute_nil class_idx
    assert_operator marker_idx, :<, class_idx
    assert_includes result, "def greet"
  end

  test "insert_annotation inserts before module when module wrapper exists" do
    original = <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      module App
        class App::User < App::UserRecord
        end
      end
    RUBY

    annotation = "# == Schema Information ==\n# content\n# == End Schema Information =="
    result = Annotator.insert_annotation(original, annotation)
    lines = result.lines

    marker_idx = lines.index { |l| l.include?("# == Schema Information ==") }
    module_idx = lines.index { |l| l.include?("module App") }
    class_idx = lines.index { |l| l.include?("class App::User") }

    refute_nil marker_idx
    refute_nil module_idx
    refute_nil class_idx
    assert_operator marker_idx, :<, module_idx
    assert_operator module_idx, :<, class_idx
  end

  test "insert_annotation prepends when no class definition exists" do
    original = "# just a comment\nsome_code\n"
    annotation = "# == Schema Information ==\n# content\n# == End Schema Information =="
    result = Annotator.insert_annotation(original, annotation)

    assert result.start_with?("# == Schema Information ==")
    assert_includes result, "some_code"
  end

  test "insert_annotation preserves code outside markers" do
    original = <<~RUBY
      # typed: strict

      # == Schema Information ==
      # old
      # == End Schema Information ==

      class User < UserRecord
        CONSTANT = 42

        def hello
          "world"
        end
      end
    RUBY

    annotation = "# == Schema Information ==\n# new\n# == End Schema Information =="
    result = Annotator.insert_annotation(original, annotation)

    assert_includes result, "CONSTANT = 42"
    assert_includes result, '"world"'
    assert_includes result, "# typed: strict"
  end

  test "annotate! writes annotation to model file" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "user.rb")
      File.write(path, "class User < UserRecord\nend\n")

      ctx = build_ctx(table: simple_users_table)
      Annotator.annotate!(path, ctx)

      content = File.read(path)

      assert_includes content, "# == Schema Information =="
      assert_includes content, "# Table name: users"
      assert_includes content, "# == End Schema Information =="
      assert_includes content, "class User < UserRecord"
    end
  end

  test "annotate! updates existing annotation without duplicating" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "user.rb")
      ctx = build_ctx(table: simple_users_table)

      File.write(path, "class User < UserRecord\nend\n")
      Annotator.annotate!(path, ctx)
      Annotator.annotate!(path, ctx)

      content = File.read(path)
      count = content.scan("# == Schema Information ==").length

      assert_equal 1, count, "Annotation should appear exactly once"
    end
  end

  test "full annotation for simple table matches expected output" do
    table = make_table("users", columns: [
                         col("id", default: "nextval('users_id_seq'::regclass)"),
                         str_col("name")
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    expected = <<~ANNOTATION.chomp
      # == Schema Information ==
      #
      # Table name: users
      # Primary key: id (integer, not null)
      #
      # id   :integer          not null, default(nextval('users_id_seq'::regclass)), primary key
      # name :string           not null
      #
      # == End Schema Information ==
    ANNOTATION

    assert_equal expected, block
  end

  test "full annotation with nullable and default columns" do
    table = make_table("products", columns: [
                         col("id", default: "nextval('products_id_seq'::regclass)"),
                         str_col("name"),
                         col("price", type: "numeric", udt: "numeric"),
                         col("stock", default: "0"),
                         col("description", type: "text", udt: "text", nullable: true)
                       ])
    ctx = build_ctx(table: table)
    block = Annotator.build_annotation(ctx)

    assert_match(/^# description\s+:string$/, block)
    assert_match(/^# stock\s+:integer\s+not null, default\(0\)$/, block)
    assert_match(/^# price\s+:decimal\s+not null$/, block)

    block.lines.each do |line|
      refute_match(/[ \t]+$/, line.chomp, "Trailing whitespace found: #{line.inspect}")
    end
  end

  test "full annotation with associations matches expected output" do
    table = make_table("users", columns: [
                         col("id", default: "nextval('users_id_seq'::regclass)"),
                         str_col("name")
                       ])
    ctx = build_ctx(
      table: table,
      has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }],
      belongs_to: [{ method_name: "company", fk_attr: "company_id", target_pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)

    expected = <<~ANNOTATION.chomp
      # == Schema Information ==
      #
      # Table name: users
      # Primary key: id (integer, not null)
      #
      # id   :integer          not null, default(nextval('users_id_seq'::regclass)), primary key
      # name :string           not null
      #
      # Associations:
      # has_many   :posts    FK: posts.user_id -> users.id
      # belongs_to :company  FK: users.company_id -> company.id
      #
      # == End Schema Information ==
    ANNOTATION

    assert_equal expected, block
  end

  test "full annotation with enums and associations" do
    table = make_table("users", columns: [
                         col("id", default: "nextval('users_id_seq'::regclass)"),
                         str_col("name"),
                         HakumiORM::Codegen::ColumnInfo.new(
                           name: "role", data_type: "USER-DEFINED", udt_name: "users_role",
                           nullable: false, default: "'reader'", max_length: nil, enum_values: %w[admin reader]
                         )
                       ])
    predicates = [
      { column: "role", enum_class: "UsersRoleEnum", const: "ADMIN", method_name: "role_admin?" },
      { column: "role", enum_class: "UsersRoleEnum", const: "READER", method_name: "role_reader?" }
    ]
    ctx = build_ctx(
      table: table,
      enum_predicates: predicates,
      has_many: [{ method_name: "posts", fk_attr: "user_id", pk_attr: "id" }]
    )
    block = Annotator.build_annotation(ctx)

    expected = <<~ANNOTATION.chomp
      # == Schema Information ==
      #
      # Table name: users
      # Primary key: id (integer, not null)
      #
      # id   :integer          not null, default(nextval('users_id_seq'::regclass)), primary key
      # name :string           not null
      # role :enum(UsersRoleEnum) not null, default('reader')
      #
      # Enums:
      # role :UsersRoleEnum [admin, reader]
      #        predicates: role_admin?, role_reader?
      #
      # Associations:
      # has_many :posts  FK: posts.user_id -> users.id
      #
      # == End Schema Information ==
    ANNOTATION

    assert_equal expected, block
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
      assert_includes code, "# Table name: users"
      assert_includes code, "# Primary key: id"
      assert_includes code, "# id"
      assert_includes code, "# name"
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

      assert_includes code, "# Table name: users"
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
      assert_includes code, "# Table name: users"
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
      lines = code.lines.grep(/^#\s+\w+\s+:(integer|string|boolean)/)
      col_names = lines.map { |l| l.strip.split(/\s+/)[1] }

      assert_equal col_names.sort, col_names
    end
  end

  test "generated annotations have zero trailing whitespace across all models" do
    Dir.mktmpdir do |dir|
      gen_dir = File.join(dir, "generated")
      models_dir = File.join(dir, "models")

      tables = build_users_posts_tables
      gen = HakumiORM::Codegen::Generator.new(tables, opts(gen_dir, models_dir: models_dir))
      gen.generate!

      Dir[File.join(models_dir, "*.rb")].each do |model_file|
        content = File.read(model_file)
        content.lines.each_with_index do |line, idx|
          stripped = line.chomp

          refute_match(/\s+$/, stripped, "#{File.basename(model_file)}:#{idx + 1} has trailing whitespace")
        end
      end
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

  def simple_users_table
    make_table("users", columns: [pk_col("users"), str_col("name"), str_col("email")])
  end

  def build_ctx(table:, has_many: [], has_one: [], belongs_to: [], has_many_through: [],
                custom_has_many: [], custom_has_one: [], enum_predicates: [])
    Context.new(
      table: table,
      dialect: @dialect,
      associations: Annotator::AssociationSets.new(
        has_many: has_many,
        has_one: has_one,
        belongs_to: belongs_to,
        has_many_through: has_many_through,
        custom_has_many: custom_has_many,
        custom_has_one: custom_has_one
      ),
      enum_predicates: enum_predicates
    )
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
