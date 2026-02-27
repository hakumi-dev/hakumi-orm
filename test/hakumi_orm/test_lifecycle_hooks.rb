# typed: false
# frozen_string_literal: true

require "test_helper"

class TestLifecycleHooks < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @prev_adapter = HakumiORM.config.adapter
    HakumiORM.adapter = @adapter
    @adapter.stub_result("DELETE", [], affected: 1)
    @adapter.stub_result("UPDATE", [["1", "Alice", "alice@test.com", nil, "t"]], affected: 1)
    @adapter.stub_result("INSERT", [["1", "Alice", "alice@test.com", nil, "t"]])
    HookTracker.reset!
    remove_hooks!
    install_hooks!
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
    HookTracker.reset!
    remove_hooks!
  end

  def install_hooks!
    UserRecord::Contract.define_singleton_method(:on_all) do |record, e|
      e.add(:name, "cannot be blank") if record.name.strip.empty?
    end
    UserRecord::Contract.define_singleton_method(:on_destroy) do |record, e|
      e.add(:base, "cannot be deleted") if record.email == "undeletable@test.com"
      HookTracker.track(:on_destroy, record.id)
    end
    UserRecord::Contract.define_singleton_method(:after_create) do |record, _adapter|
      HookTracker.track(:after_create, record.id)
    end
    UserRecord::Contract.define_singleton_method(:after_update) do |record, _adapter|
      HookTracker.track(:after_update, record.id)
    end
    UserRecord::Contract.define_singleton_method(:after_destroy) do |record, _adapter|
      HookTracker.track(:after_destroy, record.id)
    end
  end

  def remove_hooks!
    sc = UserRecord::Contract.singleton_class
    %i[on_all on_destroy after_create after_update after_destroy].each do |m|
      sc.remove_method(m) if sc.method_defined?(m, false)
    end
  end

  test "on_destroy is called before destroy!" do
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)
    user.destroy!(adapter: @adapter)

    assert_includes HookTracker.calls, [:on_destroy, 1]
  end

  test "on_destroy can prevent deletion by adding errors" do
    user = UserRecord.new(id: 1, name: "Alice", email: "undeletable@test.com", age: nil, active: true)

    err = assert_raises(HakumiORM::ValidationError) { user.destroy!(adapter: @adapter) }

    assert_includes err.errors.messages[:base], "cannot be deleted"
    refute(@adapter.executed_queries.any? { |q| q[:sql].include?("DELETE") })
  end

  test "on_destroy receives the record" do
    user = UserRecord.new(id: 42, name: "Bob", email: "bob@test.com", age: 30, active: false)
    user.destroy!(adapter: @adapter)

    assert_includes HookTracker.calls, [:on_destroy, 42]
  end

  test "after_destroy is called after successful destroy!" do
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)
    user.destroy!(adapter: @adapter)

    assert_includes HookTracker.calls, [:after_destroy, 1]
  end

  test "after_destroy is not called when on_destroy prevents deletion" do
    user = UserRecord.new(id: 1, name: "Alice", email: "undeletable@test.com", age: nil, active: true)

    assert_raises(HakumiORM::ValidationError) { user.destroy!(adapter: @adapter) }

    refute(HookTracker.calls.any? { |c| c[0] == :after_destroy })
  end

  test "after_destroy is not called when DELETE affects 0 rows" do
    @adapter.stub_result("DELETE", [], affected: 0)
    user = UserRecord.new(id: 999, name: "Ghost", email: "ghost@test.com", age: nil, active: true)

    assert_raises(HakumiORM::Error) { user.destroy!(adapter: @adapter) }

    refute(HookTracker.calls.any? { |c| c[0] == :after_destroy })
  end

  test "on_destroy fires before after_destroy" do
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)
    user.destroy!(adapter: @adapter)

    on_idx = HookTracker.calls.index { |c| c[0] == :on_destroy }
    after_idx = HookTracker.calls.index { |c| c[0] == :after_destroy }

    assert_operator on_idx, :<, after_idx
  end

  test "after_create is called after successful save!" do
    new_user = UserRecord.build(name: "Alice", email: "alice@test.com", active: true)
    validated = new_user.validate!
    validated.save!(adapter: @adapter)

    assert_includes HookTracker.calls, [:after_create, 1]
  end

  test "after_create is not called when validation fails" do
    new_user = UserRecord.build(name: "", email: "alice@test.com", active: true)

    assert_raises(HakumiORM::ValidationError) { new_user.validate! }

    refute(HookTracker.calls.any? { |c| c[0] == :after_create })
  end

  test "after_update is called after successful update!" do
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)
    user.update!(name: "Bob", adapter: @adapter)

    assert_includes HookTracker.calls, [:after_update, 1]
  end

  test "after_update is not called when validation fails" do
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)

    assert_raises(HakumiORM::ValidationError) { user.update!(name: "", adapter: @adapter) }

    refute(HookTracker.calls.any? { |c| c[0] == :after_update })
  end

  test "after_update is not called when UPDATE returns no rows" do
    @adapter.stub_result("UPDATE", [])
    user = UserRecord.new(id: 1, name: "Alice", email: "alice@test.com", age: nil, active: true)

    assert_raises(HakumiORM::Error) { user.update!(name: "Bob", adapter: @adapter) }

    refute(HookTracker.calls.any? { |c| c[0] == :after_update })
  end

  test "after_create is not called when INSERT returns no rows" do
    @adapter.stub_result("INSERT", [])
    new_user = UserRecord.build(name: "Alice", email: "alice@test.com", active: true)
    validated = new_user.validate!

    assert_raises(HakumiORM::Error) { validated.save!(adapter: @adapter) }

    refute(HookTracker.calls.any? { |c| c[0] == :after_create })
  end

  test "after_commit fires after successful transaction" do
    committed = false
    @adapter.transaction do |txn|
      txn.after_commit { committed = true }
      @adapter.exec("INSERT INTO t VALUES (1)")
    end

    assert committed
  end

  test "after_commit does not fire on rollback" do
    committed = false
    assert_raises(RuntimeError) do
      @adapter.transaction do |txn|
        txn.after_commit { committed = true }
        raise "boom"
      end
    end

    refute committed
  end

  test "after_rollback fires on transaction failure" do
    rolled_back = false
    assert_raises(RuntimeError) do
      @adapter.transaction do |txn|
        txn.after_rollback { rolled_back = true }
        raise "boom"
      end
    end

    assert rolled_back
  end

  test "after_rollback does not fire on successful commit" do
    rolled_back = false
    @adapter.transaction do |txn|
      txn.after_rollback { rolled_back = true }
    end

    refute rolled_back
  end

  test "multiple after_commit callbacks fire in registration order" do
    order = []
    @adapter.transaction do |txn|
      txn.after_commit { order << :first }
      txn.after_commit { order << :second }
    end

    assert_equal %i[first second], order
  end

  test "after_commit registered inside savepoint fires after top-level commit" do
    committed = false
    @adapter.transaction do |_txn|
      @adapter.transaction(requires_new: true) do |inner|
        inner.after_commit { committed = true }
      end

      refute committed, "should not fire after savepoint release"
    end

    assert committed, "should fire after top-level commit"
  end

  test "after_rollback registered inside savepoint fires on top-level rollback" do
    rolled_back = false
    assert_raises(RuntimeError) do
      @adapter.transaction do |_txn|
        @adapter.transaction(requires_new: true) do |inner|
          inner.after_rollback { rolled_back = true }
        end
        raise "outer boom"
      end
    end

    assert rolled_back
  end

  test "after_commit in rolled-back savepoint does NOT fire on top-level commit" do
    committed = false
    @adapter.transaction do |_txn|
      @adapter.transaction(requires_new: true) do |inner|
        inner.after_commit { committed = true }
        raise "savepoint boom"
      end
    rescue RuntimeError
      nil
    end

    refute committed, "callback from rolled-back savepoint must be discarded"
  end

  test "after_rollback in rolled-back savepoint fires immediately" do
    rolled_back = false
    @adapter.transaction do |_txn|
      assert_raises(RuntimeError) do
        @adapter.transaction(requires_new: true) do |inner|
          inner.after_rollback { rolled_back = true }
          raise "savepoint boom"
        end
      end

      assert rolled_back, "after_rollback should fire when savepoint rolls back"
    end
  end

  test "after_commit outside transaction raises" do
    assert_raises(HakumiORM::Error) do
      @adapter.after_commit { "nope" }
    end
  end

  test "after_commit runs all callbacks even when one raises" do
    calls = []
    err = assert_raises(RuntimeError) do
      @adapter.transaction do |txn|
        txn.after_commit { calls << :first }
        txn.after_commit { raise "boom in second" }
        txn.after_commit { calls << :third }
      end
    end

    assert_equal %i[first third], calls
    assert_equal "boom in second", err.message
  end

  test "after_rollback runs all callbacks even when one raises" do
    calls = []
    err = assert_raises(RuntimeError) do
      @adapter.transaction do |txn|
        txn.after_rollback { calls << :first }
        txn.after_rollback { raise "rollback boom" }
        txn.after_rollback { calls << :third }
        raise "trigger rollback"
      end
    end

    assert_equal %i[first third], calls
    assert_equal "rollback boom", err.message
  end

  test "callbacks are cleared after transaction completes" do
    side_effect_count = 0
    @adapter.transaction do |txn|
      txn.after_commit { side_effect_count += 1 }
    end

    @adapter.transaction do |_txn|
      @adapter.exec("SELECT 1")
    end

    assert_equal 1, side_effect_count
  end
end

module HookTracker
  CallEntry = T.type_alias { [Symbol, Integer] }

  @calls = T.let([], T::Array[CallEntry])

  class << self
    extend T::Sig

    sig { returns(T::Array[CallEntry]) }
    attr_reader :calls

    sig { void }
    def reset!
      @calls = []
    end

    sig { params(event: Symbol, id: Integer).void }
    def track(event, id)
      @calls << [event, id]
    end
  end
end
