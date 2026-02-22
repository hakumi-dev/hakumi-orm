# typed: false
# frozen_string_literal: true

require "test_helper"
require "hakumi_orm/adapter/sqlite"

class TestAdapterSqlite < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Adapter::Sqlite.connect(":memory:")
    @adapter.exec("CREATE TABLE test_items (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
  end

  def teardown
    @adapter.close
  end

  test "exec_params inserts and returns affected rows" do
    result = @adapter.exec_params("INSERT INTO test_items (name, score) VALUES (?, ?)", ["alice", "9.5"])

    assert_equal 1, result.affected_rows
  end

  test "exec_params selects rows as string arrays" do
    @adapter.exec_params("INSERT INTO test_items (name, score) VALUES (?, ?)", ["bob", "7.2"])

    result = @adapter.exec_params("SELECT name, score FROM test_items WHERE name = ?", ["bob"])

    assert_equal 1, result.row_count
    assert_equal "bob", result.fetch_value(0, 0)
    assert_equal "7.2", result.fetch_value(0, 1)
  end

  test "exec runs plain SQL" do
    @adapter.exec("INSERT INTO test_items (name, score) VALUES ('carol', 8.0)")

    result = @adapter.exec("SELECT COUNT(*) FROM test_items")

    assert_equal "1", result.fetch_value(0, 0)
  end

  test "get_value returns nil for NULL columns" do
    @adapter.exec_params("INSERT INTO test_items (name, score) VALUES (?, ?)", ["dave", nil])

    result = @adapter.exec_params("SELECT score FROM test_items WHERE name = ?", ["dave"])

    assert_nil result.get_value(0, 0)
  end

  test "values returns all rows" do
    @adapter.exec("INSERT INTO test_items (name, score) VALUES ('a', 1.0), ('b', 2.0)")

    result = @adapter.exec("SELECT name FROM test_items ORDER BY name")

    assert_equal [["a"], ["b"]], result.values
  end

  test "column_values returns a single column" do
    @adapter.exec("INSERT INTO test_items (name, score) VALUES ('x', 1.0), ('y', 2.0)")

    result = @adapter.exec("SELECT name, score FROM test_items ORDER BY name")

    assert_equal %w[x y], result.column_values(0)
  end

  test "prepare and exec_prepared work" do
    @adapter.prepare("ins", "INSERT INTO test_items (name, score) VALUES (?, ?)")
    @adapter.exec_prepared("ins", ["eve", "5.5"])

    result = @adapter.exec("SELECT name FROM test_items")

    assert_equal "eve", result.fetch_value(0, 0)
  end

  test "exec_prepared raises on unknown statement" do
    assert_raises(HakumiORM::Error) do
      @adapter.exec_prepared("nonexistent", [])
    end
  end

  test "transaction commits on success" do
    @adapter.transaction do |_txn|
      @adapter.exec("INSERT INTO test_items (name, score) VALUES ('txn_ok', 1.0)")
    end

    result = @adapter.exec("SELECT COUNT(*) FROM test_items WHERE name = 'txn_ok'")

    assert_equal "1", result.fetch_value(0, 0)
  end

  test "transaction rolls back on error" do
    assert_raises(RuntimeError) do
      @adapter.transaction do |_txn|
        @adapter.exec("INSERT INTO test_items (name, score) VALUES ('txn_fail', 1.0)")
        raise "boom"
      end
    end

    result = @adapter.exec("SELECT COUNT(*) FROM test_items WHERE name = 'txn_fail'")

    assert_equal "0", result.fetch_value(0, 0)
  end

  test "dialect is Sqlite" do
    assert_instance_of HakumiORM::Dialect::Sqlite, @adapter.dialect
  end
end
