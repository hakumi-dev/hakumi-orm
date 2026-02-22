# typed: false
# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "hakumi_orm/migration"

class TestMigrationRunner < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
    @dir = Dir.mktmpdir("hakumi_migrations")
    @runner = HakumiORM::Migration::Runner.new(@adapter, migrations_path: @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  test "creates hakumi_migrations table on first run" do
    @runner.migrate!
    sqls = executed_sqls

    assert(sqls.any? { |s| s.include?("hakumi_migrations") && s.include?("CREATE TABLE") })
  end

  test "migrate runs pending migrations in timestamp order" do
    write_migration("20260101000000_alpha_step.rb", "AlphaStep", "ALPHA_UP", "ALPHA_DOWN")
    write_migration("20260102000000_beta_step.rb", "BetaStep", "BETA_UP", "BETA_DOWN")

    @runner.migrate!
    sqls = executed_sqls

    alpha_idx = sqls.index("ALPHA_UP")
    beta_idx = sqls.index("BETA_UP")

    refute_nil alpha_idx
    refute_nil beta_idx
    assert_operator alpha_idx, :<, beta_idx
  end

  test "migrate skips already-run migrations" do
    write_migration("20260101000000_gamma_step.rb", "GammaStep", "GAMMA_UP", "GAMMA_DOWN")

    @adapter.stub_result("SELECT version", [["20260101000000"]])
    @runner.migrate!

    refute_includes executed_sqls, "GAMMA_UP"
  end

  test "migrate records version after successful migration" do
    write_migration("20260101000000_delta_step.rb", "DeltaStep", "DELTA_UP", "DELTA_DOWN")

    @runner.migrate!
    sqls = executed_sqls

    assert(sqls.any? { |s| s.include?("INSERT") && s.include?("hakumi_migrations") && s.include?("20260101000000") })
  end

  test "rollback runs down on the last migration" do
    write_migration("20260101000000_epsilon_step.rb", "EpsilonStep", "EPSILON_UP", "EPSILON_DOWN")

    @adapter.stub_result("SELECT version", [["20260101000000"]])
    @runner.rollback!

    assert_includes executed_sqls, "EPSILON_DOWN"
  end

  test "rollback removes version from tracking table" do
    write_migration("20260101000000_zeta_step.rb", "ZetaStep", "ZETA_UP", "ZETA_DOWN")

    @adapter.stub_result("SELECT version", [["20260101000000"]])
    @runner.rollback!

    assert(executed_sqls.any? { |s| s.include?("DELETE") && s.include?("20260101000000") })
  end

  test "rollback with count rolls back N migrations in reverse order" do
    write_migration("20260101000000_eta_step.rb", "EtaStep", "ETA_UP", "ETA_DOWN")
    write_migration("20260102000000_theta_step.rb", "ThetaStep", "THETA_UP", "THETA_DOWN")

    @adapter.stub_result("SELECT version", [["20260101000000"], ["20260102000000"]])
    @runner.rollback!(count: 2)
    sqls = executed_sqls

    theta_idx = sqls.index("THETA_DOWN")
    eta_idx = sqls.index("ETA_DOWN")

    refute_nil theta_idx
    refute_nil eta_idx
    assert_operator theta_idx, :<, eta_idx
  end

  test "status returns list of migrations with up/down state" do
    write_migration("20260101000000_iota_step.rb", "IotaStep", "IOTA_UP", "IOTA_DOWN")
    write_migration("20260102000000_kappa_step.rb", "KappaStep", "KAPPA_UP", "KAPPA_DOWN")

    @adapter.stub_result("SELECT version", [["20260101000000"]])
    statuses = @runner.status

    assert_equal 2, statuses.length
    assert_equal "up", statuses[0][:status]
    assert_equal "20260101000000", statuses[0][:version]
    assert_equal "down", statuses[1][:status]
    assert_equal "20260102000000", statuses[1][:version]
  end

  test "current_version returns the latest applied version" do
    @adapter.stub_result("SELECT version", [["20260101000000"], ["20260102000000"]])

    assert_equal "20260102000000", @runner.current_version
  end

  test "current_version returns nil when no migrations applied" do
    assert_nil @runner.current_version
  end

  test "ignores non-migration files in directory" do
    File.write(File.join(@dir, "README.md"), "not a migration")
    write_migration("20260101000000_lambda_step.rb", "LambdaStep", "LAMBDA_UP", "LAMBDA_DOWN")

    @runner.migrate!

    assert_includes executed_sqls, "LAMBDA_UP"
  end

  test "migrate does not record version when migration raises" do
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class NuStep < HakumiORM::Migration
        def up
          raise "boom"
        end
        def down; end
      end
    RUBY
    File.write(File.join(@dir, "20260101000000_nu_step.rb"), content)

    assert_raises(RuntimeError) { @runner.migrate! }

    refute(executed_sqls.any? { |s| s.include?("INSERT") && s.include?("hakumi_migrations") })
  end

  test "load_migration raises clear error when class does not inherit from Migration" do
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class XiStep
        def up; end
        def down; end
      end
    RUBY
    File.write(File.join(@dir, "20260101000000_xi_step.rb"), content)

    err = assert_raises(HakumiORM::Error) { @runner.migrate! }

    assert_includes err.message, "XiStep"
    assert_includes err.message, "must inherit from HakumiORM::Migration"
  end

  test "load_migration raises clear error when class name does not match filename" do
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class WrongClassName < HakumiORM::Migration
        def up; end
        def down; end
      end
    RUBY
    File.write(File.join(@dir, "20260101000000_omicron_step.rb"), content)

    err = assert_raises(HakumiORM::Error) { @runner.migrate! }

    assert_includes err.message, "OmicronStep"
  end

  test "migrate handles empty migrations directory" do
    @runner.migrate!

    assert(executed_sqls.any? { |s| s.include?("CREATE TABLE") })
    refute(executed_sqls.any? { |s| s.include?("INSERT") })
  end

  test "migrate runs files sorted by timestamp regardless of insertion order" do
    write_migration("20260103000000_third_step.rb", "ThirdStep", "THIRD", "THIRD_DOWN")
    write_migration("20260101000000_first_step.rb", "FirstStep", "FIRST", "FIRST_DOWN")
    write_migration("20260102000000_second_step.rb", "SecondStep", "SECOND", "SECOND_DOWN")

    @runner.migrate!
    sqls = executed_sqls

    first_idx = sqls.index("FIRST")
    second_idx = sqls.index("SECOND")
    third_idx = sqls.index("THIRD")

    refute_nil first_idx
    refute_nil second_idx
    refute_nil third_idx
    assert_operator first_idx, :<, second_idx
    assert_operator second_idx, :<, third_idx
  end

  test "migrate acquires and releases advisory lock on PG" do
    write_migration("20260101000000_pi_step.rb", "PiStep", "PI_UP", "PI_DOWN")

    @runner.migrate!
    sqls = executed_sqls

    lock_idx = sqls.index { |s| s.include?("pg_advisory_lock") }
    unlock_idx = sqls.index { |s| s.include?("pg_advisory_unlock") }
    migration_idx = sqls.index("PI_UP")

    refute_nil lock_idx
    refute_nil unlock_idx
    refute_nil migration_idx
    assert_operator lock_idx, :<, migration_idx
    assert_operator migration_idx, :<, unlock_idx
  end

  test "advisory lock is released even when migration raises" do
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class RhoStep < HakumiORM::Migration
        def up
          raise "intentional failure"
        end
        def down; end
      end
    RUBY
    File.write(File.join(@dir, "20260101000000_rho_step.rb"), content)

    assert_raises(RuntimeError) { @runner.migrate! }

    assert(executed_sqls.any? { |s| s.include?("pg_advisory_unlock") })
  end

  test "advisory lock is skipped for SQLite (no advisory lock support)" do
    sqlite_adapter = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Sqlite.new)
    runner = HakumiORM::Migration::Runner.new(sqlite_adapter, migrations_path: @dir)
    write_migration("20260101000000_sigma_step.rb", "SigmaStep", "SIGMA_UP", "SIGMA_DOWN")

    runner.migrate!
    sqls = sqlite_adapter.executed_queries.map { |q| q[:sql] }

    refute(sqls.any? { |s| s.include?("advisory") || s.include?("GET_LOCK") })
    assert_includes sqls, "SIGMA_UP"
  end

  test "disable_ddl_transaction! migration skips transaction wrapper" do
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class MuStep < HakumiORM::Migration
        disable_ddl_transaction!

        def up
          execute "CREATE INDEX CONCURRENTLY idx_test ON users (email)"
        end
        def down
          execute "DROP INDEX CONCURRENTLY idx_test"
        end
      end
    RUBY
    File.write(File.join(@dir, "20260101000000_mu_step.rb"), content)

    @runner.migrate!

    assert_includes executed_sqls, "CREATE INDEX CONCURRENTLY idx_test ON users (email)"
    refute(executed_sqls.any? { |s| s.include?("BEGIN") }, "should not wrap in transaction")
  end

  private

  def write_migration(filename, class_name, up_sql, down_sql)
    content = <<~RUBY
      # typed: false
      # frozen_string_literal: true

      class #{class_name} < HakumiORM::Migration
        def up
          execute "#{up_sql}"
        end
        def down
          execute "#{down_sql}"
        end
      end
    RUBY
    File.write(File.join(@dir, filename), content)
  end

  def executed_sqls
    @adapter.executed_queries.map { |q| q[:sql] }
  end
end
