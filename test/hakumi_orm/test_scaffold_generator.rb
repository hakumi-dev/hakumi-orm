# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestScaffoldGenerator < HakumiORM::TestCase
  def setup
    HakumiORM.reset_config!
  end

  test "creates model and contract files" do
    Dir.mktmpdir do |dir|
      models = File.join(dir, "models")
      contracts = File.join(dir, "contracts")
      config = HakumiORM.config
      config.models_dir = models
      config.contracts_dir = contracts

      gen = HakumiORM::ScaffoldGenerator.new("users", config)
      created = gen.run!

      assert_equal 2, created.length
      assert_path_exists File.join(models, "user.rb")
      assert_path_exists File.join(contracts, "user_contract.rb")

      model_code = File.read(File.join(models, "user.rb"))

      assert_includes model_code, "class User < UserRecord"
      assert_includes model_code, "# typed: strict"

      contract_code = File.read(File.join(contracts, "user_contract.rb"))

      assert_includes contract_code, "class UserRecord::Contract < UserRecord::BaseContract"
    end
  ensure
    HakumiORM.reset_config!
  end

  test "skips existing files" do
    Dir.mktmpdir do |dir|
      models = File.join(dir, "models")
      config = HakumiORM.config
      config.models_dir = models
      config.contracts_dir = nil

      FileUtils.mkdir_p(models)
      File.write(File.join(models, "user.rb"), "existing")

      gen = HakumiORM::ScaffoldGenerator.new("users", config)
      created = gen.run!

      assert_empty created

      assert_equal "existing", File.read(File.join(models, "user.rb"))
    end
  ensure
    HakumiORM.reset_config!
  end

  test "handles module_name" do
    Dir.mktmpdir do |dir|
      models = File.join(dir, "models")
      contracts = File.join(dir, "contracts")
      config = HakumiORM.config
      config.models_dir = models
      config.contracts_dir = contracts
      config.module_name = "MyApp"

      gen = HakumiORM::ScaffoldGenerator.new("users", config)
      gen.run!

      model_code = File.read(File.join(models, "user.rb"))

      assert_includes model_code, "module MyApp"
      assert_includes model_code, "class MyApp::User < MyApp::UserRecord"

      contract_code = File.read(File.join(contracts, "user_contract.rb"))

      assert_includes contract_code, "module MyApp"
      assert_includes contract_code, "MyApp::UserRecord::Contract < MyApp::UserRecord::BaseContract"
    end
  ensure
    HakumiORM.reset_config!
  end

  test "singularizes table name" do
    Dir.mktmpdir do |dir|
      models = File.join(dir, "models")
      config = HakumiORM.config
      config.models_dir = models
      config.contracts_dir = nil

      gen = HakumiORM::ScaffoldGenerator.new("categories", config)
      gen.run!

      assert_path_exists File.join(models, "category.rb")

      code = File.read(File.join(models, "category.rb"))

      assert_includes code, "class Category < CategoryRecord"
    end
  ensure
    HakumiORM.reset_config!
  end

  test "returns empty when no dirs configured" do
    config = HakumiORM.config
    config.models_dir = nil
    config.contracts_dir = nil

    gen = HakumiORM::ScaffoldGenerator.new("users", config)
    created = gen.run!

    assert_empty created
  ensure
    HakumiORM.reset_config!
  end
end
