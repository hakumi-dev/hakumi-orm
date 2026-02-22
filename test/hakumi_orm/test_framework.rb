# typed: false
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/hakumi_orm"

class TestFrameworkRegistry < Minitest::Test
  def setup
    HakumiORM::Framework.reset!
  end

  def test_detect_standalone_with_no_registrations
    assert_equal :standalone, HakumiORM::Framework.detect
  end

  def test_register_and_detect
    HakumiORM::Framework.register(:test_fw) { true }

    assert_equal :test_fw, HakumiORM::Framework.detect
  end

  def test_register_not_detected
    HakumiORM::Framework.register(:test_fw) { false }

    assert_equal :standalone, HakumiORM::Framework.detect
  end

  def test_first_match_wins
    HakumiORM::Framework.register(:first) { true }
    HakumiORM::Framework.register(:second) { true }

    assert_equal :first, HakumiORM::Framework.detect
  end

  def test_skips_false_detectors
    HakumiORM::Framework.register(:absent) { false }
    HakumiORM::Framework.register(:present) { true }

    assert_equal :present, HakumiORM::Framework.detect
  end

  def test_registered_lists_names
    HakumiORM::Framework.register(:alpha) { false }
    HakumiORM::Framework.register(:beta) { false }

    assert_equal %i[alpha beta], HakumiORM::Framework.registered
  end

  def test_reset_clears_current_and_detectors
    HakumiORM::Framework.register(:test_fw) { true }
    HakumiORM::Framework.current = :test_fw

    HakumiORM::Framework.reset!

    assert_nil HakumiORM::Framework.current
    assert_empty HakumiORM::Framework.registered
  end
end

class TestFrameworkCurrent < Minitest::Test
  def setup
    HakumiORM::Framework.reset!
  end

  def test_current_defaults_to_nil
    assert_nil HakumiORM::Framework.current
  end

  def test_current_setter
    HakumiORM::Framework.current = :rails

    assert_equal :rails, HakumiORM::Framework.current
  end

  def test_rails_query
    HakumiORM::Framework.current = :rails

    assert_predicate HakumiORM::Framework, :rails?
    refute_predicate HakumiORM::Framework, :sinatra?
    refute_predicate HakumiORM::Framework, :standalone?
  end

  def test_sinatra_query
    HakumiORM::Framework.current = :sinatra

    assert_predicate HakumiORM::Framework, :sinatra?
    refute_predicate HakumiORM::Framework, :rails?
    refute_predicate HakumiORM::Framework, :standalone?
  end

  def test_standalone_when_nil
    assert_predicate HakumiORM::Framework, :standalone?
    refute_predicate HakumiORM::Framework, :rails?
    refute_predicate HakumiORM::Framework, :sinatra?
  end

  def test_standalone_when_explicit
    HakumiORM::Framework.current = :standalone

    assert_predicate HakumiORM::Framework, :standalone?
  end

  def test_custom_framework
    HakumiORM::Framework.register(:hanami) { true }
    HakumiORM::Framework.current = :hanami

    assert_equal :hanami, HakumiORM::Framework.current
    refute_predicate HakumiORM::Framework, :rails?
    refute_predicate HakumiORM::Framework, :sinatra?
    refute_predicate HakumiORM::Framework, :standalone?
  end
end

class TestRailsConfig < Minitest::Test
  def setup
    HakumiORM.reset_config!
    require_relative "../../lib/hakumi_orm/framework/rails_config"
  end

  def teardown
    HakumiORM.reset_config!
  end

  def test_sets_logger
    logger = Logger.new($stdout)
    config = HakumiORM.config

    HakumiORM::Framework::RailsConfig.apply_defaults(config, logger: logger)

    assert_equal logger, config.logger
  end

  def test_sets_models_dir_when_nil
    config = HakumiORM.config

    assert_nil config.models_dir

    HakumiORM::Framework::RailsConfig.apply_defaults(config)

    assert_equal "app/models", config.models_dir
  end

  def test_sets_contracts_dir_when_nil
    config = HakumiORM.config

    assert_nil config.contracts_dir

    HakumiORM::Framework::RailsConfig.apply_defaults(config)

    assert_equal "app/contracts", config.contracts_dir
  end

  def test_preserves_existing_models_dir
    config = HakumiORM.config
    config.models_dir = "lib/models"

    HakumiORM::Framework::RailsConfig.apply_defaults(config)

    assert_equal "lib/models", config.models_dir
  end

  def test_preserves_existing_contracts_dir
    config = HakumiORM.config
    config.contracts_dir = "lib/contracts"

    HakumiORM::Framework::RailsConfig.apply_defaults(config)

    assert_equal "lib/contracts", config.contracts_dir
  end

  def test_nil_logger_by_default
    config = HakumiORM.config

    HakumiORM::Framework::RailsConfig.apply_defaults(config)

    assert_nil config.logger
  end
end

class TestSinatraConfig < Minitest::Test
  def setup
    HakumiORM.reset_config!
    require_relative "../../lib/hakumi_orm/framework/sinatra_config"
  end

  def teardown
    HakumiORM.reset_config!
  end

  def test_sets_logger
    logger = Logger.new($stdout)
    config = HakumiORM.config

    HakumiORM::Framework::SinatraConfig.apply_defaults(config, logger: logger)

    assert_equal logger, config.logger
  end

  def test_sets_paths_from_root
    config = HakumiORM.config

    HakumiORM::Framework::SinatraConfig.apply_defaults(config, root: "/tmp/myapp")

    assert_equal "/tmp/myapp/db/generated", config.output_dir
    assert_equal "/tmp/myapp/db/migrate", config.migrations_path
    assert_equal "/tmp/myapp/db/associations", config.associations_path
  end

  def test_skips_paths_without_root
    config = HakumiORM.config
    original_output = config.output_dir

    HakumiORM::Framework::SinatraConfig.apply_defaults(config)

    assert_equal original_output, config.output_dir
  end

  def test_skips_logger_when_nil
    config = HakumiORM.config
    config.logger = nil

    HakumiORM::Framework::SinatraConfig.apply_defaults(config)

    assert_nil config.logger
  end
end

class TestFrameworkThirdPartyRegistration < Minitest::Test
  def setup
    HakumiORM::Framework.reset!
  end

  def test_register_custom_framework
    HakumiORM::Framework.register(:hanami) { true }

    assert_includes HakumiORM::Framework.registered, :hanami
    assert_equal :hanami, HakumiORM::Framework.detect
  end

  def test_multiple_frameworks_priority
    HakumiORM::Framework.register(:rails) { false }
    HakumiORM::Framework.register(:hanami) { true }
    HakumiORM::Framework.register(:sinatra) { true }

    assert_equal :hanami, HakumiORM::Framework.detect
  end

  def test_register_overwrites_existing
    HakumiORM::Framework.register(:test_fw) { false }

    assert_equal :standalone, HakumiORM::Framework.detect

    HakumiORM::Framework.register(:test_fw) { true }

    assert_equal :test_fw, HakumiORM::Framework.detect
  end
end
