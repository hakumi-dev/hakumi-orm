# typed: false
# frozen_string_literal: true

require "test_helper"

class TestTransactionParity < HakumiORM::TestCase
  DialectCase = Struct.new(:name, :dialect, keyword_init: true)

  def setup
    @dialects = [
      DialectCase.new(name: :postgresql, dialect: HakumiORM::Dialect::Postgresql.new),
      DialectCase.new(name: :mysql, dialect: HakumiORM::Dialect::Mysql.new),
      DialectCase.new(name: :sqlite, dialect: HakumiORM::Dialect::Sqlite.new)
    ]
  end

  test "transaction and savepoint SQL flow is identical across dialects" do
    @dialects.each do |dialect_case|
      adapter = HakumiORM::Test::MockAdapter.new(dialect: dialect_case.dialect)

      adapter.transaction do
        adapter.exec("INSERT INTO t VALUES (1)")
        adapter.transaction(requires_new: true) do
          adapter.exec("INSERT INTO t VALUES (2)")
        end
        adapter.exec("INSERT INTO t VALUES (3)")
      end

      sqls = adapter.executed_queries.map { |q| q[:sql] }

      assert_equal [
        "BEGIN",
        "INSERT INTO t VALUES (1)",
        "SAVEPOINT hakumi_sp_1",
        "INSERT INTO t VALUES (2)",
        "RELEASE SAVEPOINT hakumi_sp_1",
        "INSERT INTO t VALUES (3)",
        "COMMIT"
      ], sqls, "unexpected SQL flow for #{dialect_case.name}"
    end
  end

  test "savepoint rollback preserves outer transaction across dialects" do
    @dialects.each do |dialect_case|
      adapter = HakumiORM::Test::MockAdapter.new(dialect: dialect_case.dialect)

      adapter.transaction do
        adapter.exec("INSERT INTO t VALUES (1)")

        assert_raises(RuntimeError) do
          adapter.transaction(requires_new: true) do
            adapter.exec("INSERT INTO t VALUES (2)")
            raise "inner boom"
          end
        end

        adapter.exec("INSERT INTO t VALUES (3)")
      end

      sqls = adapter.executed_queries.map { |q| q[:sql] }

      assert_equal [
        "BEGIN",
        "INSERT INTO t VALUES (1)",
        "SAVEPOINT hakumi_sp_1",
        "INSERT INTO t VALUES (2)",
        "ROLLBACK TO SAVEPOINT hakumi_sp_1",
        "INSERT INTO t VALUES (3)",
        "COMMIT"
      ], sqls, "unexpected rollback flow for #{dialect_case.name}"
    end
  end

  test "nested callback semantics are identical across dialects" do
    @dialects.each do |dialect_case|
      adapter = HakumiORM::Test::MockAdapter.new(dialect: dialect_case.dialect)
      fired = []

      adapter.transaction do
        adapter.after_commit { fired << :outer_commit }
        adapter.after_rollback { fired << :outer_rollback }

        adapter.transaction(requires_new: true) do
          adapter.after_commit { fired << :inner_commit }
          adapter.after_rollback { fired << :inner_rollback }
          adapter.exec("SELECT 1")
        end

        refute_includes fired, :inner_commit, "inner after_commit must wait for top-level commit (#{dialect_case.name})"
      end

      assert_equal %i[outer_commit inner_commit], fired, "unexpected callback order for #{dialect_case.name}"
    end
  end

  test "rolled-back savepoint callbacks are discarded or fired correctly across dialects" do
    @dialects.each do |dialect_case|
      adapter = HakumiORM::Test::MockAdapter.new(dialect: dialect_case.dialect)
      fired = []

      adapter.transaction do
        adapter.after_commit { fired << :outer_commit }

        assert_raises(RuntimeError) do
          adapter.transaction(requires_new: true) do
            adapter.after_commit { fired << :inner_commit_should_not_fire }
            adapter.after_rollback { fired << :inner_rollback }
            raise "savepoint boom"
          end
        end
      end

      assert_equal %i[inner_rollback outer_commit], fired, "unexpected rolled-back savepoint callback behavior for #{dialect_case.name}"
    end
  end
end
