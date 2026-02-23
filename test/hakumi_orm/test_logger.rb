# typed: false
# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class TestLogger < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @prev_adapter = HakumiORM.config.adapter
    @prev_logger = HakumiORM.config.logger
    HakumiORM.adapter = @adapter
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
    HakumiORM.config.logger = @prev_logger
  end

  test "logger is nil by default" do
    HakumiORM.reset_config!

    assert_nil HakumiORM.config.logger
  ensure
    HakumiORM.config.adapter = @prev_adapter
  end

  test "logger is configurable" do
    io = StringIO.new
    logger = Logger.new(io)
    HakumiORM.config.logger = logger

    assert_equal logger, HakumiORM.config.logger
  end

  test "exec_params logs SQL with timing when logger is set" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)

    UserRelation.new.where(UserSchema::ACTIVE.eq(true)).to_a(adapter: @adapter)

    output = io.string

    assert_includes output, "SELECT"
    assert_includes output, '"users"'
    assert_match(/\(\d+\.\d+ms\)/, output)
  end

  test "exec_params does not log when logger is nil" do
    HakumiORM.config.logger = nil

    UserRelation.new.to_a(adapter: @adapter)
  end

  test "count logs SQL through exec_prepared path" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    @adapter.stub_result("COUNT(*)", [["5"]])

    UserRelation.new.count(adapter: @adapter)

    assert_includes io.string, "COUNT(*)"
  end

  test "logger includes bind params" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)

    UserRelation.new.where(UserSchema::AGE.gt(18)).to_a(adapter: @adapter)

    assert_includes io.string, "18"
  end

  test "configure block sets logger" do
    io = StringIO.new
    logger = Logger.new(io)

    HakumiORM.configure do |c|
      c.logger = logger
    end

    assert_equal logger, HakumiORM.config.logger
  end

  test "log_level= creates a logger with the given level" do
    HakumiORM.config.log_level = :debug

    logger = HakumiORM.config.logger

    refute_nil logger
    assert_equal Logger::DEBUG, logger.level
  end

  test "log_level= with :warn sets WARN level" do
    HakumiORM.config.log_level = :warn

    assert_equal Logger::WARN, HakumiORM.config.logger&.level
  end

  test "log_level= raises on invalid level" do
    assert_raises(ArgumentError) { HakumiORM.config.log_level = :verbose }
  end

  test "log_level= logger produces output at correct level" do
    old_stdout = $stdout
    $stdout = StringIO.new
    HakumiORM.config.log_level = :debug

    UserRelation.new.to_a(adapter: @adapter)

    assert_includes $stdout.string, "[HakumiORM]"
  ensure
    $stdout = old_stdout
  end
end
