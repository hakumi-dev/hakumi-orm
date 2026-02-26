# typed: false
# frozen_string_literal: true

require "test_helper"

class LockingRowResult < HakumiORM::Test::MockResult
  def initialize(data = [], affected: nil)
    super
  end
end

class OptimisticLockMockAdapter < HakumiORM::Test::MockAdapter
  UPDATE_SQL = 'UPDATE "locking_users" SET "name" = $1, "lock_version" = "lock_version" + 1 WHERE "locking_users"."id" = $2 AND "locking_users"."lock_version" = $3'
  FIND_SQL = 'SELECT "locking_users"."id", "locking_users"."name", "locking_users"."lock_version" FROM "locking_users" WHERE "locking_users"."id" = $1 LIMIT 1'

  attr_reader :rows

  def initialize
    super(dialect: HakumiORM::Dialect::Postgresql.new)
    @rows = { 1 => { id: 1, name: "Alice", lock_version: 0 } }
  end

  def exec_params(sql, params)
    start = log_query_start
    @executed_queries << { sql: sql, params: params }
    result = if sql == UPDATE_SQL
               update_row(params)
             elsif sql == FIND_SQL
               find_row(params)
             else
               super_result(sql)
             end
    log_query_done(sql, params, start)
    result
  end

  private

  def super_result(sql)
    @results.each do |pattern, result|
      return result if sql.include?(pattern)
    end
    @default_result
  end

  def update_row(params)
    new_name, id, expected_lock_version = params
    row = @rows[id]
    return LockingRowResult.new([], affected: 0) if row.nil?
    return LockingRowResult.new([], affected: 0) unless row[:lock_version] == expected_lock_version

    row[:name] = new_name
    row[:lock_version] += 1
    LockingRowResult.new([], affected: 1)
  end

  def find_row(params)
    id = params.fetch(0)
    row = @rows[id]
    return LockingRowResult.new([], affected: 0) if row.nil?

    LockingRowResult.new([[row[:id], row[:name], row[:lock_version]]], affected: 1)
  end
end

class LockingUserRecord
  attr_reader :id, :name, :lock_version

  UPDATE_SQL = OptimisticLockMockAdapter::UPDATE_SQL
  FIND_SQL = OptimisticLockMockAdapter::FIND_SQL

  def initialize(id:, name:, lock_version:)
    @id = id
    @name = name
    @lock_version = lock_version
  end

  def self.from_result_first(result)
    return nil if result.row_count.zero?

    row = result.values.first
    new(id: row.fetch(0), name: row.fetch(1), lock_version: row.fetch(2))
  end

  def self.find(id, adapter:)
    result = adapter.exec_params(FIND_SQL, [id])
    from_result_first(result)
  ensure
    result&.close
  end

  def update!(adapter:, name: @name)
    return self if name == @name

    result = adapter.exec_params(UPDATE_SQL, [name, @id, @lock_version])
    raise HakumiORM::StaleObjectError, "Attempted to update a stale #{self.class.name}" if result.affected_rows.zero?

    result.close
    record = self.class.find(@id, adapter: adapter)
    raise HakumiORM::StaleObjectError, "Attempted to update a stale #{self.class.name}" unless record

    record
  ensure
    result&.close
  end
end

class TestOptimisticLocking < HakumiORM::TestCase
  def setup
    @adapter = OptimisticLockMockAdapter.new
  end

  test "successful update increments lock_version and returns refreshed record" do
    record = LockingUserRecord.new(id: 1, name: "Alice", lock_version: 0)

    updated = record.update!(name: "Alice 2", adapter: @adapter)

    assert_equal "Alice 2", updated.name
    assert_equal 1, updated.lock_version
    assert_equal 2, @adapter.executed_queries.length
    assert_equal [1], @adapter.executed_queries.last.fetch(:params)
  end

  test "stale update raises StaleObjectError" do
    @adapter.rows[1][:lock_version] = 3
    record = LockingUserRecord.new(id: 1, name: "Alice", lock_version: 0)

    assert_raises(HakumiORM::StaleObjectError) do
      record.update!(name: "Alice 2", adapter: @adapter)
    end
  end

  test "two concurrent updates trigger lost update protection on second writer" do
    first = LockingUserRecord.new(id: 1, name: "Alice", lock_version: 0)
    second = LockingUserRecord.new(id: 1, name: "Alice", lock_version: 0)

    updated = first.update!(name: "Alice first", adapter: @adapter)

    assert_equal 1, updated.lock_version

    err = assert_raises(HakumiORM::StaleObjectError) do
      second.update!(name: "Alice second", adapter: @adapter)
    end

    assert_includes err.message, "stale"
    assert_equal "Alice first", @adapter.rows[1][:name]
    assert_equal 1, @adapter.rows[1][:lock_version]
  end

  test "no-op update does not execute SQL" do
    record = LockingUserRecord.new(id: 1, name: "Alice", lock_version: 0)

    same = record.update!(name: "Alice", adapter: @adapter)

    assert_same record, same
    assert_empty @adapter.executed_queries
  end
end
