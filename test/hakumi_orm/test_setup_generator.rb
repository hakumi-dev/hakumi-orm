# typed: false
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../lib/hakumi_orm"

class TestSetupGeneratorStandalone < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("hakumi_install")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_creates_standard_directories
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    result = gen.run!

    %w[db/migrate db/associations db/generated].each do |dir|
      assert Dir.exist?(File.join(@tmpdir, dir))
      assert_path_exists File.join(@tmpdir, dir, ".keep")
      assert_includes result[:created], dir
    end
  end

  def test_does_not_create_rails_directories
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    gen.run!

    refute Dir.exist?(File.join(@tmpdir, "app/models"))
    refute Dir.exist?(File.join(@tmpdir, "app/contracts"))
  end

  def test_creates_standalone_initializer
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    gen.run!

    path = File.join(@tmpdir, "config/hakumi/orm.rb")

    assert_path_exists path
    content = File.read(path)

    assert_includes content, 'require "hakumi_orm"'
    assert_includes content, "HakumiORM.configure"
    assert_includes content, "database_url"
    assert_includes content, "Rakefile"
  end

  def test_does_not_create_rails_initializer
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    gen.run!

    refute_path_exists File.join(@tmpdir, "config/initializers/hakumi/orm.rb")
  end

  def test_skips_existing_directories
    FileUtils.mkdir_p(File.join(@tmpdir, "db/migrate"))

    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    result = gen.run!

    assert_includes result[:skipped], "db/migrate"
    refute_includes result[:created], "db/migrate"
  end

  def test_skips_existing_initializer
    FileUtils.mkdir_p(File.join(@tmpdir, "config/hakumi"))
    File.write(File.join(@tmpdir, "config/hakumi/orm.rb"), "existing content")

    gen = HakumiORM::SetupGenerator.new(root: @tmpdir)
    result = gen.run!

    assert_includes result[:skipped], "config/hakumi/orm.rb"
    assert_equal "existing content", File.read(File.join(@tmpdir, "config/hakumi/orm.rb"))
  end

  def test_idempotent
    gen1 = HakumiORM::SetupGenerator.new(root: @tmpdir)
    first = gen1.run!

    refute_empty first[:created]

    gen2 = HakumiORM::SetupGenerator.new(root: @tmpdir)
    second = gen2.run!

    assert_empty second[:created]
    refute_empty second[:skipped]
  end
end

class TestSetupGeneratorRails < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("hakumi_install_rails")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_creates_rails_directories
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :rails)
    result = gen.run!

    %w[db/migrate db/associations db/generated app/models app/contracts].each do |dir|
      assert Dir.exist?(File.join(@tmpdir, dir))
      assert_path_exists File.join(@tmpdir, dir, ".keep")
      assert_includes result[:created], dir
    end
  end

  def test_creates_rails_initializer
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :rails)
    gen.run!

    path = File.join(@tmpdir, "config/initializers/hakumi/orm.rb")

    assert_path_exists path
    content = File.read(path)

    assert_includes content, "HakumiORM.configure"
    assert_includes content, "database_url"
    refute_includes content, 'require "hakumi_orm"'
    refute_includes content, "Rakefile"
  end

  def test_does_not_create_standalone_initializer
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :rails)
    gen.run!

    refute_path_exists File.join(@tmpdir, "config/hakumi/orm.rb")
  end

  def test_skips_existing_rails_dirs
    FileUtils.mkdir_p(File.join(@tmpdir, "app/models"))

    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :rails)
    result = gen.run!

    assert_includes result[:skipped], "app/models"
    refute_includes result[:created], "app/models"
  end

  def test_initializer_includes_replica_example
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :rails)
    gen.run!

    content = File.read(File.join(@tmpdir, "config/initializers/hakumi/orm.rb"))

    assert_includes content, "database_config(:replica)"
    assert_includes content, "REPLICA_DATABASE_URL"
  end
end

class TestSetupGeneratorSinatra < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("hakumi_install_sinatra")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_sinatra_uses_standalone_template
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :sinatra)
    gen.run!

    path = File.join(@tmpdir, "config/hakumi/orm.rb")

    assert_path_exists path
    content = File.read(path)

    assert_includes content, 'require "hakumi_orm"'
  end

  def test_sinatra_does_not_create_rails_dirs
    gen = HakumiORM::SetupGenerator.new(root: @tmpdir, framework: :sinatra)
    gen.run!

    refute Dir.exist?(File.join(@tmpdir, "app/models"))
    refute Dir.exist?(File.join(@tmpdir, "app/contracts"))
  end
end
