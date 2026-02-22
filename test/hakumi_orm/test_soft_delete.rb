# typed: false
# frozen_string_literal: true

require "test_helper"

class TestSoftDelete < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @prev_adapter = HakumiORM.config.adapter
    HakumiORM.adapter = @adapter
  end

  def teardown
    HakumiORM.config.adapter = @prev_adapter
  end

  test "default scope filters out soft-deleted records" do
    ArticleRelation.new.to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "IS NULL"
    assert_includes @adapter.last_sql, '"articles"."deleted_at"'
  end

  test "with_deleted removes the soft-delete filter from SELECT" do
    ArticleRelation.new.with_deleted.to_a(adapter: @adapter)

    refute_includes @adapter.last_sql, "IS NULL"
  end

  test "only_deleted replaces filter with IS NOT NULL" do
    ArticleRelation.new.only_deleted.to_a(adapter: @adapter)

    assert_includes @adapter.last_sql, "IS NOT NULL"
  end

  test "unscoped removes soft-delete filter" do
    ArticleRelation.new.unscoped.to_a(adapter: @adapter)

    refute_includes @adapter.last_sql, "IS NULL"
    refute_includes @adapter.last_sql, "IS NOT NULL"
  end

  test "count without where uses prepared statement with soft-delete filter" do
    @adapter.stub_result("COUNT(*)", [["10"]])

    result = ArticleRelation.new.count(adapter: @adapter)

    assert_equal 10, result
    assert_includes @adapter.last_sql, "IS NULL"
  end

  test "count with with_deleted does NOT use the prepared statement" do
    @adapter.stub_default([["25"]])

    result = ArticleRelation.new.with_deleted.count(adapter: @adapter)

    assert_equal 25, result
    refute_includes @adapter.last_sql, "IS NULL"
  end

  test "count with only_deleted uses IS NOT NULL" do
    @adapter.stub_default([["3"]])

    result = ArticleRelation.new.only_deleted.count(adapter: @adapter)

    assert_equal 3, result
    assert_includes @adapter.last_sql, "IS NOT NULL"
  end

  test "count with unscoped has no WHERE clause" do
    @adapter.stub_default([["50"]])

    result = ArticleRelation.new.unscoped.count(adapter: @adapter)

    assert_equal 50, result
    refute_includes @adapter.last_sql, "WHERE"
  end

  test "count sequence: default then with_deleted does not reuse cached statement" do
    @adapter.stub_result("IS NULL", [["10"]])
    @adapter.stub_default([["25"]])

    default_count = ArticleRelation.new.count(adapter: @adapter)
    all_count = ArticleRelation.new.with_deleted.count(adapter: @adapter)

    assert_equal 10, default_count
    assert_equal 25, all_count
    refute_includes @adapter.last_sql, "IS NULL"
  end

  test "count with with_deleted plus extra where respects both" do
    @adapter.stub_default([["7"]])

    ArticleRelation.new.with_deleted.where(ArticleSchema::ID.gt(0)).count(adapter: @adapter)

    refute_includes @adapter.last_sql, "IS NULL"
    assert_includes @adapter.last_sql, ">"
  end

  test "delete_all generates DELETE FROM on soft-delete table" do
    @adapter.stub_default([], affected: 3)

    ArticleRelation.new.where(ArticleSchema::TITLE.eq("old")).delete_all(adapter: @adapter)

    assert_includes @adapter.last_sql, "DELETE FROM"
  end
end
