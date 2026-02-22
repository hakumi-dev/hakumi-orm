# typed: false
# frozen_string_literal: true

require "test_helper"

class TestTransaction < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
  end

  test "top-level transaction issues BEGIN and COMMIT" do
    @adapter.transaction do |_a|
      @adapter.exec("INSERT INTO t VALUES (1)")
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }

    assert_equal ["BEGIN", "INSERT INTO t VALUES (1)", "COMMIT"], sqls
  end

  test "top-level transaction rolls back on error" do
    assert_raises(RuntimeError) do
      @adapter.transaction do |_a|
        @adapter.exec("INSERT INTO t VALUES (1)")
        raise "boom"
      end
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }

    assert_equal ["BEGIN", "INSERT INTO t VALUES (1)", "ROLLBACK"], sqls
  end

  test "nested transaction without requires_new skips savepoint" do
    @adapter.transaction do |_a|
      @adapter.transaction do |_inner|
        @adapter.exec("INSERT INTO t VALUES (1)")
      end
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }

    assert_equal ["BEGIN", "INSERT INTO t VALUES (1)", "COMMIT"], sqls
  end

  test "nested transaction with requires_new uses savepoint" do
    @adapter.transaction do |_a|
      @adapter.transaction(requires_new: true) do |_inner|
        @adapter.exec("INSERT INTO t VALUES (1)")
      end
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }
    expected = [
      "BEGIN",
      "SAVEPOINT hakumi_sp_1",
      "INSERT INTO t VALUES (1)",
      "RELEASE SAVEPOINT hakumi_sp_1",
      "COMMIT"
    ]

    assert_equal expected, sqls
  end

  test "nested savepoint rolls back on error without affecting outer" do
    @adapter.transaction do |_a|
      @adapter.exec("INSERT INTO t VALUES (1)")

      assert_raises(RuntimeError) do
        @adapter.transaction(requires_new: true) do |_inner|
          @adapter.exec("INSERT INTO t VALUES (2)")
          raise "inner boom"
        end
      end

      @adapter.exec("INSERT INTO t VALUES (3)")
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }
    expected = [
      "BEGIN",
      "INSERT INTO t VALUES (1)",
      "SAVEPOINT hakumi_sp_1",
      "INSERT INTO t VALUES (2)",
      "ROLLBACK TO SAVEPOINT hakumi_sp_1",
      "INSERT INTO t VALUES (3)",
      "COMMIT"
    ]

    assert_equal expected, sqls
  end

  test "doubly nested savepoints use incremented names" do
    @adapter.transaction do |_a|
      @adapter.transaction(requires_new: true) do |_inner|
        @adapter.transaction(requires_new: true) do |_deep|
          @adapter.exec("SELECT 1")
        end
      end
    end

    sqls = @adapter.executed_queries.map { |q| q[:sql] }
    expected = [
      "BEGIN",
      "SAVEPOINT hakumi_sp_1",
      "SAVEPOINT hakumi_sp_2",
      "SELECT 1",
      "RELEASE SAVEPOINT hakumi_sp_2",
      "RELEASE SAVEPOINT hakumi_sp_1",
      "COMMIT"
    ]

    assert_equal expected, sqls
  end
end
