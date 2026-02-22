# typed: false
# frozen_string_literal: true

require "test_helper"
require "fileutils"

class TestTypeScaffold < HakumiORM::TestCase
  def setup
    super
    @tmpdir = File.join(Dir.tmpdir, "hakumi_scaffold_test_#{Process.pid}")
    FileUtils.mkdir_p(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    super
  end

  test "generates a field file for a custom type" do
    HakumiORM::Codegen::TypeScaffold.generate(name: "money", output_dir: @tmpdir)

    path = File.join(@tmpdir, "money_field.rb")

    assert_path_exists path, "Expected #{path} to exist"

    content = File.read(path)

    assert_includes content, "class MoneyField < ::HakumiORM::Field"
    assert_includes content, "StrBind"
  end

  test "generates a registration initializer file" do
    HakumiORM::Codegen::TypeScaffold.generate(name: "money", output_dir: @tmpdir)

    path = File.join(@tmpdir, "money_type.rb")

    assert_path_exists path, "Expected #{path} to exist"

    content = File.read(path)

    assert_includes content, "TypeRegistry.register"
    assert_includes content, "name: :money"
    assert_includes content, "MoneyField"
  end

  test "generated field file is valid Ruby" do
    HakumiORM::Codegen::TypeScaffold.generate(name: "money", output_dir: @tmpdir)

    path = File.join(@tmpdir, "money_field.rb")
    result = system("ruby", "-c", path, out: File::NULL, err: File::NULL)

    assert result, "Generated field file has syntax errors"
  end

  test "generated registration file is valid Ruby" do
    HakumiORM::Codegen::TypeScaffold.generate(name: "money", output_dir: @tmpdir)

    path = File.join(@tmpdir, "money_type.rb")
    result = system("ruby", "-c", path, out: File::NULL, err: File::NULL)

    assert result, "Generated registration file has syntax errors"
  end

  test "does not overwrite existing files" do
    path = File.join(@tmpdir, "money_field.rb")
    File.write(path, "existing content")

    HakumiORM::Codegen::TypeScaffold.generate(name: "money", output_dir: @tmpdir)

    assert_equal "existing content", File.read(path)
  end

  test "handles snake_case names with underscores" do
    HakumiORM::Codegen::TypeScaffold.generate(name: "ip_address", output_dir: @tmpdir)

    path = File.join(@tmpdir, "ip_address_field.rb")

    assert_path_exists path

    content = File.read(path)

    assert_includes content, "class IpAddressField"
  end
end
