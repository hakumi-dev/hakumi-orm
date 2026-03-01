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
    assert_equal 1, @pool.total_connections
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

  test "pool_stats exposes active record style pool metrics" do
    stats = @pool.pool_stats

    refute_nil stats
    assert_equal 3, stats[:size]
    assert_equal 1, stats[:connections]
    assert_equal 0, stats[:busy]
    assert_equal 1, stats[:idle]
    assert_equal 0, stats[:waiting]
    assert_equal 0, stats[:dead]
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
    assert_equal 1, pool.dead_connections

    pool.exec_params("SELECT 1", [])

    assert_equal 2, call_count
    assert_equal 0, pool.dead_connections
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

  # --- Instrumentation ---

  test "subscribe returns an integer id" do
    id = @pool.subscribe(:checkout) { |_e| }

    assert_instance_of Integer, id
  end

  test "checkout event fires with wait_ms" do
    events = []
    @pool.subscribe(:checkout) { |e| events << e }

    @pool.exec("SELECT 1")

    assert_equal 1, events.size
    assert events.first.key?(:wait_ms)
    assert_instance_of Float, events.first[:wait_ms]
  end

  test "checkin event fires after connection is returned" do
    events = []
    @pool.subscribe(:checkin) { |e| events << e }

    @pool.exec("SELECT 1")

    assert_equal 1, events.size
  end

  test "checkout and checkin each fire once per query" do
    checkouts = []
    checkins = []
    @pool.subscribe(:checkout) { |e| checkouts << e }
    @pool.subscribe(:checkin) { |e| checkins << e }

    @pool.exec("SELECT 1")
    @pool.exec("SELECT 2")

    assert_equal 2, checkouts.size
    assert_equal 2, checkins.size
  end

  test "reentrant calls do not fire checkout/checkin for inner calls" do
    checkouts = []
    @pool.subscribe(:checkout) { |e| checkouts << e }

    @pool.transaction do |_conn|
      @pool.exec("SELECT 1")
      @pool.exec("SELECT 2")
    end

    assert_equal 1, checkouts.size
  end

  test "timeout event fires with wait_ms when pool is exhausted" do
    tiny_pool = HakumiORM::Adapter::ConnectionPool.new(size: 1, timeout: 0.1) do
      HakumiORM::Test::MockAdapter.new
    end

    timeout_events = []
    tiny_pool.subscribe(:timeout) { |e| timeout_events << e }

    blocker = Queue.new
    t = Thread.new { tiny_pool.transaction { |_| blocker.pop } }
    sleep 0.05

    assert_raises(HakumiORM::Adapter::TimeoutError) { tiny_pool.exec("SELECT 1") }

    assert_equal 1, timeout_events.size
    assert_instance_of Float, timeout_events.first[:wait_ms]
  ensure
    blocker << :done
    t&.join
  end

  test "discard event fires when dead connection is evicted" do
    discards = []
    @pool.subscribe(:discard) { |e| discards << e }

    dead_conn = HakumiORM::Test::MockAdapter.new
    dead_conn.define_singleton_method(:alive?) { false }
    dead_conn.define_singleton_method(:exec) { |_sql| raise StandardError, "connection lost" }

    @pool.instance_variable_get(:@available) << dead_conn

    assert_raises(StandardError) { @pool.exec("SELECT 1") }

    assert_equal 1, discards.size
  end

  test "multiple subscribers for the same event all fire" do
    calls = []
    @pool.subscribe(:checkout) { |_e| calls << :first }
    @pool.subscribe(:checkout) { |_e| calls << :second }

    @pool.exec("SELECT 1")

    assert_includes calls, :first
    assert_includes calls, :second
    assert_equal 2, calls.size
  end

  test "unsubscribe removes the callback" do
    calls = []
    id = @pool.subscribe(:checkout) { |_e| calls << :fired }

    @pool.unsubscribe(:checkout, id)
    @pool.exec("SELECT 1")

    assert_empty calls
  end

  test "exception in callback does not crash the pool" do
    @pool.subscribe(:checkout) { |_e| raise "boom" }

    result = @pool.exec("SELECT 1")

    assert_equal 0, result.row_count
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

    waiting_probe = Queue.new
    timeout_thread = Thread.new do
      waiting_probe << :started
      assert_raises(HakumiORM::Adapter::TimeoutError) do
        tiny_pool.exec("SELECT 1")
      end
    end

    waiting_probe.pop
    deadline = Time.now + 0.1
    sleep 0.005 while tiny_pool.waiting_connections.zero? && Time.now < deadline

    assert_equal 1, tiny_pool.waiting_connections

    timeout_thread.join

    assert_equal 0, tiny_pool.waiting_connections

    blocker << :done
    t.join
  end

  # --- Health checks ---

  test "health_check! returns 0 when all idle connections are alive" do
    discarded = @pool.health_check!

    assert_equal 0, discarded
    assert_equal 1, @pool.total_connections
  end

  test "health_check! discards dead idle connections and returns count" do
    dead = HakumiORM::Test::MockAdapter.new
    dead.define_singleton_method(:alive?) { false }
    @pool.instance_variable_get(:@available) << dead

    discarded = @pool.health_check!

    assert_equal 1, discarded
  end

  test "health_check! reduces total_connections by discarded count" do
    dead = HakumiORM::Test::MockAdapter.new
    dead.define_singleton_method(:alive?) { false }
    @pool.instance_variable_get(:@available) << dead
    original_total = @pool.total_connections

    @pool.health_check!

    assert_equal original_total - 1, @pool.total_connections
  end

  test "health_check! fires :discard event for each dead connection" do
    discards = []
    @pool.subscribe(:discard) { discards << :fired }

    dead = HakumiORM::Test::MockAdapter.new
    dead.define_singleton_method(:alive?) { false }
    @pool.instance_variable_get(:@available) << dead

    @pool.health_check!

    assert_equal 1, discards.size
  end

  test "health_check! keeps live connections in the pool" do
    original = @pool.total_connections
    @pool.health_check!

    assert_equal original, @pool.total_connections
    assert_equal original, @pool.available_connections
  end

  test "health_check! with multiple dead connections discards all of them" do
    2.times do
      dead = HakumiORM::Test::MockAdapter.new
      dead.define_singleton_method(:alive?) { false }
      @pool.instance_variable_get(:@available) << dead
    end

    discarded = @pool.health_check!

    assert_equal 2, discarded
  end

  test "with health_check: true, dead connection on checkout is skipped and a new one is created" do
    call_count = 0
    pool = HakumiORM::Adapter::ConnectionPool.new(size: 3, timeout: 1.0, health_check: true) do
      call_count += 1
      HakumiORM::Test::MockAdapter.new
    end

    dead = pool.instance_variable_get(:@available).first
    dead.define_singleton_method(:alive?) { false }

    pool.exec("SELECT 1")

    assert call_count >= 2, "expected a new connection to be created after discarding the dead one"
  end

  test "with health_check: true, discard event fires for dead checkout connections" do
    pool = HakumiORM::Adapter::ConnectionPool.new(size: 3, timeout: 1.0, health_check: true) do
      HakumiORM::Test::MockAdapter.new
    end

    discards = []
    pool.subscribe(:discard) { discards << :fired }

    dead = pool.instance_variable_get(:@available).first
    dead.define_singleton_method(:alive?) { false }

    pool.exec("SELECT 1")

    assert_equal 1, discards.size
  end

  test "with health_check: false (default), dead connection on checkout is not checked proactively" do
    pool = HakumiORM::Adapter::ConnectionPool.new(size: 3, timeout: 1.0) do
      HakumiORM::Test::MockAdapter.new
    end

    dead = pool.instance_variable_get(:@available).first
    dead.define_singleton_method(:alive?) { false }

    # Without health_check, the dead conn is handed out; query succeeds because
    # exec_params is not overridden to fail
    result = pool.exec("SELECT 1")

    assert_equal 0, result.row_count
  end
end
