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
    @prev_pretty_sql_logs = HakumiORM.config.pretty_sql_logs
    @prev_colorize_sql_logs = HakumiORM.config.colorize_sql_logs
    @prev_log_filter_parameters = HakumiORM.config.log_filter_parameters
    @prev_log_filter_mask = HakumiORM.config.log_filter_mask
    HakumiORM.adapter = @adapter
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
    HakumiORM.config.logger = @prev_logger
    HakumiORM.config.pretty_sql_logs = @prev_pretty_sql_logs
    HakumiORM.config.colorize_sql_logs = @prev_colorize_sql_logs
    HakumiORM.config.log_filter_parameters = @prev_log_filter_parameters
    HakumiORM.config.log_filter_mask = @prev_log_filter_mask
  end

  private

  # Propagates the current HakumiORM.config logging settings to @adapter.
  # Call this after changing any config.logger / config.log_filter_* values
  # and before running queries that should produce log output.
  def sync_log_config!
    @adapter.assign_log_config(
      HakumiORM::Adapter::Base::LogConfig.new(
        logger: HakumiORM.config.logger,
        pretty_sql_logs: HakumiORM.config.pretty_sql_logs,
        colorize_sql_logs: HakumiORM.config.colorize_sql_logs,
        log_filter_parameters: HakumiORM.config.log_filter_parameters,
        log_filter_mask: HakumiORM.config.log_filter_mask
      )
    )
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
    sync_log_config!

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
    sync_log_config!
    @adapter.stub_result("COUNT(*)", [["5"]])

    UserRelation.new.count(adapter: @adapter)

    assert_includes io.string, "COUNT(*)"
  end

  test "logger includes bind params" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    sync_log_config!

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
    sync_log_config!

    UserRelation.new.to_a(adapter: @adapter)

    assert_includes $stdout.string, "[HakumiORM]"
  ensure
    $stdout = old_stdout
  end

  test "accepts any object implementing Loggable" do
    custom = CustomLogger.new
    HakumiORM.config.logger = custom
    sync_log_config!

    UserRelation.new.to_a(adapter: @adapter)

    assert_includes custom.messages, :debug
  end

  test "pretty_sql_logs formats output without ANSI when colors are disabled" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    HakumiORM.config.pretty_sql_logs = true
    HakumiORM.config.colorize_sql_logs = false
    sync_log_config!

    UserRelation.new.where(UserSchema::ACTIVE.eq(true)).to_a(adapter: @adapter)

    output = io.string

    assert_includes output, "HakumiORM SQL"
    assert_includes output, "SELECT"
    refute_includes output, "\e["
  end

  test "pretty sql formatter supports prepared note" do
    formatted = HakumiORM::SqlLogFormatter.format(
      elapsed_ms: 1.23,
      sql: "select * from users",
      params: [],
      note: "PREPARED",
      colorize: false
    )

    assert_includes formatted, "HakumiORM SQL"
    assert_includes formatted, "select * from users"
    assert_includes formatted, "[PREPARED]"
  end

  test "pretty sql formatter colorizes when enabled" do
    formatted = HakumiORM::SqlLogFormatter.format(
      elapsed_ms: 1.23,
      sql: "select * from users where id = 1",
      params: [],
      note: nil,
      colorize: true
    )

    assert_includes formatted, "\e["
  end

  test "logger filters sensitive bind params based on configured patterns" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    HakumiORM.config.log_filter_parameters = ["email"]
    sync_log_config!

    UserRelation.new.where(UserSchema::EMAIL.eq("secret@example.com")).to_a(adapter: @adapter)

    output = io.string

    refute_includes output, "secret@example.com"
    assert_includes output, "[FILTERED]"
  end

  test "logger uses configurable filter mask" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    HakumiORM.config.log_filter_parameters = ["email"]
    HakumiORM.config.log_filter_mask = "[HIDDEN]"
    sync_log_config!

    UserRelation.new.where(UserSchema::EMAIL.eq("secret@example.com")).to_a(adapter: @adapter)

    output = io.string

    refute_includes output, "secret@example.com"
    assert_includes output, "[HIDDEN]"
  end

  test "logger filters insert bind params when sensitive columns are present" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    HakumiORM.config.log_filter_parameters = ["email"]
    sync_log_config!

    @adapter.exec_params(
      'INSERT INTO "users" ("email", "name") VALUES ($1, $2)',
      ["secret@example.com", "Alice"]
    )

    output = io.string

    refute_includes output, "secret@example.com"
    refute_includes output, "Alice"
    assert_includes output, "[FILTERED]"
  end

  test "transaction control statements are tagged in logs" do
    io = StringIO.new
    HakumiORM.config.logger = Logger.new(io)
    HakumiORM.config.pretty_sql_logs = false
    sync_log_config!

    @adapter.transaction do
      @adapter.exec("SELECT 1")
    end

    output = io.string

    assert_includes output, "BEGIN"
    assert_includes output, "COMMIT"
    assert_includes output, "[TRANSACTION]"
  end
end

class CustomLogger
  include HakumiORM::Loggable

  attr_reader :messages

  def initialize
    @messages = []
  end

  def debug(_message = nil, &_blk) = (@messages << :debug)
  def info(_message = nil, &_blk) = (@messages << :info)
  def warn(_message = nil, &_blk) = (@messages << :warn)
  def error(_message = nil, &_blk) = (@messages << :error)
  def fatal(_message = nil, &_blk) = (@messages << :fatal)
end
