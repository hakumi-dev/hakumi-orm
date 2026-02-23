# typed: false
# frozen_string_literal: true

require "test_helper"

class TestConnectionPool < HakumiORM::TestCase
  def setup
    @pool = HakumiORM::Adapter::ConnectionPool.new(size: 3, timeout: 1.0) do
      HakumiORM::Test::MockAdapter.new
    end
  end

  test "pool creates first connection eagerly" do
    assert_equal 1, @pool.available_connections
    assert_equal 0, @pool.active_connections
  end

  test "exec_params delegates to a connection" do
    result = @pool.exec_params("SELECT 1", [])

    assert_equal 0, result.row_count
  end

  test "exec delegates to a connection" do
    result = @pool.exec("SELECT 1")

    assert_equal 0, result.row_count
  end

  test "dialect returns shared dialect from first connection" do
    assert_instance_of HakumiORM::Dialect::Postgresql, @pool.dialect
  end

  test "pool_size returns configured size" do
    assert_equal 3, @pool.pool_size
  end

  test "transaction holds same connection for the block" do
    queries = []

    @pool.transaction do |adapter|
      adapter.exec("INSERT INTO t VALUES (1)")
      queries << "insert"
      adapter.exec("INSERT INTO t VALUES (2)")
      queries << "insert2"
    end

    assert_equal %w[insert insert2], queries
  end

  test "close shuts down all connections" do
    @pool.exec("SELECT 1")
    @pool.close

    assert_equal 0, @pool.available_connections
    assert_equal 0, @pool.active_connections
  end

  test "concurrent threads get different connections" do
    barrier = Queue.new
    conn_ids = Queue.new

    threads = Array.new(2) do
      Thread.new do
        @pool.exec_params("SELECT 1", [])
        conn_ids << Thread.current.object_id
        barrier.pop
      end
    end

    sleep 0.05
    2.times { barrier << :go }
    threads.each(&:join)

    ids = []
    ids << conn_ids.pop until conn_ids.empty?

    assert_equal 2, ids.uniq.length
  end

  test "reentrant calls within same thread reuse connection" do
    outer_conn_id = nil
    inner_conn_id = nil

    @pool.transaction do |adapter|
      outer_conn_id = adapter.object_id
      @pool.exec_params("SELECT 1", [])
      @pool.transaction do |inner_adapter|
        inner_conn_id = inner_adapter.object_id
      end
    end

    assert_equal outer_conn_id, inner_conn_id
  end

  test "dead connection is evicted from pool on error" do
    call_count = 0
    pool = HakumiORM::Adapter::ConnectionPool.new(size: 2, timeout: 1.0) do
      call_count += 1
      HakumiORM::Test::MockAdapter.new
    end

    dead_adapter = nil
    pool.transaction do |adapter|
      dead_adapter = adapter
    end

    dead_adapter.define_singleton_method(:alive?) { false }
    dead_adapter.define_singleton_method(:exec_params) { |_sql, _params| raise "connection lost" }

    assert_raises(RuntimeError) { pool.exec_params("SELECT 1", []) }

    assert_equal 0, pool.available_connections

    pool.exec_params("SELECT 1", [])

    assert_equal 2, call_count
  end

  test "healthy connection is returned to pool after query error" do
    pool = HakumiORM::Adapter::ConnectionPool.new(size: 2, timeout: 1.0) do
      HakumiORM::Test::MockAdapter.new
    end

    adapter_ref = nil
    pool.transaction do |adapter|
      adapter_ref = adapter
    end

    adapter_ref.define_singleton_method(:exec_params) do |_sql, _params|
      raise "syntax error"
    end

    assert_raises(RuntimeError) { pool.exec_params("SELECT 1", []) }

    assert_equal 1, pool.available_connections
  end

  test "prepare_exec runs both prepare and exec_prepared on same connection" do
    prepare_on = nil
    exec_on = nil

    pool = HakumiORM::Adapter::ConnectionPool.new(size: 3, timeout: 1.0) do
      adapter = HakumiORM::Test::MockAdapter.new
      adapter.define_singleton_method(:prepare) do |name, sql|
        prepare_on = object_id
        super(name, sql)
      end
      adapter.define_singleton_method(:exec_prepared) do |name, params|
        exec_on = object_id
        super(name, params)
      end
      adapter
    end

    pool.prepare_exec("stmt_test", "SELECT 1", [])

    refute_nil prepare_on
    refute_nil exec_on
    assert_equal prepare_on, exec_on
  end

  test "after_commit on pool forwards to checked-out connection" do
    calls = []

    @pool.transaction do |_txn|
      @pool.after_commit { calls << :committed }
    end

    assert_equal [:committed], calls
  end

  test "after_rollback on pool forwards to checked-out connection" do
    calls = []

    assert_raises(RuntimeError) do
      @pool.transaction do |_txn|
        @pool.after_rollback { calls << :rolled_back }
        raise "boom"
      end
    end

    assert_equal [:rolled_back], calls
  end

  test "after_commit on pool raises outside transaction" do
    err = assert_raises(HakumiORM::Error) do
      @pool.after_commit { nil }
    end

    assert_includes err.message, "only be called inside a transaction"
  end

  test "timeout raises when pool is exhausted" do
    tiny_pool = HakumiORM::Adapter::ConnectionPool.new(size: 1, timeout: 0.1) do
      HakumiORM::Test::MockAdapter.new
    end

    blocker = Queue.new
    t = Thread.new do
      tiny_pool.transaction do |_adapter|
        blocker.pop
      end
    end

    sleep 0.05

    assert_raises(HakumiORM::Adapter::TimeoutError) do
      tiny_pool.exec("SELECT 1")
    end

    blocker << :done
    t.join
  end
end
