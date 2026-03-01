# typed: false
# frozen_string_literal: true

require "test_helper"

class PreloadCall
  extend T::Sig

  attr_reader :name, :record_count, :adapter

  sig { params(name: Symbol, record_count: Integer, adapter: HakumiORM::Adapter::Base).void }
  def initialize(name:, record_count:, adapter:)
    @name = T.let(name, Symbol)
    @record_count = T.let(record_count, Integer)
    @adapter = T.let(adapter, HakumiORM::Adapter::Base)
  end
end

class TrackingRelation < UserRelation
  extend T::Sig

  sig { returns(T::Array[PreloadCall]) }
  attr_reader :calls

  sig { returns(T::Array[Symbol]) }
  attr_reader :known_names

  sig { void }
  def initialize
    super
    @calls = T.let([], T::Array[PreloadCall])
    @known_names = T.let([], T::Array[Symbol])
  end

  sig { override.params(name: Symbol, records: T::Array[UserRecord], adapter: HakumiORM::Adapter::Base).void }
  def custom_preload(name, records, adapter)
    @calls << PreloadCall.new(name: name, record_count: records.length, adapter: adapter)
  end
end

class MixedTrackingRelation < TrackingRelation
  extend T::Sig

  sig { override.params(records: T::Array[UserRecord], nodes: T::Array[HakumiORM::PreloadNode], adapter: HakumiORM::Adapter::Base, depth: Integer).void }
  def run_preloads(records, nodes, adapter, depth: 0)
    raise HakumiORM::Error, "Preload depth limit (#{MAX_PRELOAD_DEPTH}) exceeded — possible circular preload" if depth > MAX_PRELOAD_DEPTH

    nodes.each do |node|
      case node.name
      when :posts
        @known_names << :posts
      else
        custom_preload(node.name, records, adapter)
      end
    end
  end
end

class TestCustomPreload < HakumiORM::TestCase
  test "Relation#custom_preload is a no-op by default" do
    relation = UserRelation.new
    relation.custom_preload(:anything, [], @adapter)
  end

  test "run_preloads delegates unknown association to custom_preload" do
    relation = TrackingRelation.new
    node = HakumiORM::PreloadNode.new(:authored_posts)
    records = [UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)]

    relation.run_preloads(records, [node], @adapter)

    call = relation.calls.first

    assert_equal 1, relation.calls.length
    assert_equal :authored_posts, call.name
    assert_equal 1, call.record_count
    assert_equal @adapter, call.adapter
  end

  test "run_preloads dispatches known associations without custom_preload" do
    relation = MixedTrackingRelation.new
    known_node = HakumiORM::PreloadNode.new(:posts)
    custom_node = HakumiORM::PreloadNode.new(:authored_posts)
    records = [UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)]

    relation.run_preloads(records, [known_node, custom_node], @adapter)

    assert_includes relation.known_names, :posts
    assert_equal [:authored_posts], relation.calls.map(&:name)
  end

  test "custom_preload receives all records" do
    relation = TrackingRelation.new
    node = HakumiORM::PreloadNode.new(:custom_assoc)
    records = [
      UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 25, active: true),
      UserRecord.new(id: 2, name: "Bob", email: "b@c.com", age: 30, active: false)
    ]

    relation.run_preloads(records, [node], @adapter)

    assert_equal 2, relation.calls.first.record_count
  end

  test "each unknown association triggers a separate custom_preload call" do
    relation = TrackingRelation.new
    nodes = [
      HakumiORM::PreloadNode.new(:authored_posts),
      HakumiORM::PreloadNode.new(:managed_teams)
    ]
    records = [UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)]

    relation.run_preloads(records, nodes, @adapter)

    assert_equal %i[authored_posts managed_teams], relation.calls.map(&:name)
  end

  test "run_preloads raises when depth exceeds MAX_PRELOAD_DEPTH" do
    relation = TrackingRelation.new
    node = HakumiORM::PreloadNode.new(:deep)
    records = [UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)]

    err = assert_raises(HakumiORM::Error) do
      relation.run_preloads(records, [node], @adapter, depth: HakumiORM::Relation::MAX_PRELOAD_DEPTH + 1)
    end

    assert_includes err.message, "Preload depth limit"
  end

  test "run_preloads works at MAX_PRELOAD_DEPTH boundary" do
    relation = TrackingRelation.new
    node = HakumiORM::PreloadNode.new(:edge)
    records = [UserRecord.new(id: 1, name: "Alice", email: "a@b.com", age: 30, active: true)]

    relation.run_preloads(records, [node], @adapter, depth: HakumiORM::Relation::MAX_PRELOAD_DEPTH)

    assert_equal [:edge], relation.calls.map(&:name)
  end

  private

  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
  end
end
