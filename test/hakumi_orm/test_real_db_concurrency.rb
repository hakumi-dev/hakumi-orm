# typed: false
# frozen_string_literal: true

require "test_helper"

class TestRealDbConcurrency < HakumiORM::TestCase
  RealDbCase = Struct.new(:name, :adapter1, :adapter2, keyword_init: true)

  TABLE_NAME = "hakumi_concurrency_locking"

  def setup
    skip "Set HAKUMI_REAL_DB_CONCURRENCY=1 to run real DB concurrency tests" unless ENV["HAKUMI_REAL_DB_CONCURRENCY"] == "1"

    @cases = build_cases
    skip "No real DB concurrency adapters configured (PG/MySQL)" if @cases.empty?
  end

  def teardown
    @cases&.each do |db_case|
      begin
        db_case.adapter1.exec(%(DROP TABLE IF EXISTS #{quoted_table(db_case)}))&.close
      rescue StandardError
        nil
      end
      db_case.adapter1.close
      db_case.adapter2.close
    end
  end

  test "optimistic locking prevents lost updates with two real connections" do
    @cases.each do |db_case|
      create_locking_table!(db_case)
      seed_locking_row!(db_case)

      snap1 = read_locking_row(db_case, db_case.adapter1)
      snap2 = read_locking_row(db_case, db_case.adapter2)

      assert_equal 0, snap1.fetch(:lock_version), "expected initial lock_version for #{db_case.name}"
      assert_equal 0, snap2.fetch(:lock_version), "expected initial lock_version for #{db_case.name}"

      r1 = update_with_optimistic_lock(db_case, db_case.adapter1, name: "first-writer", expected_lock_version: 0)
      r2 = update_with_optimistic_lock(db_case, db_case.adapter2, name: "second-writer", expected_lock_version: 0)

      assert_equal 1, r1.affected_rows, "first writer should win for #{db_case.name}"
      assert_equal 0, r2.affected_rows, "second writer should be stale for #{db_case.name}"

      final_row = read_locking_row(db_case, db_case.adapter1)

      assert_equal "first-writer", final_row.fetch(:name), "final name mismatch for #{db_case.name}"
      assert_equal 1, final_row.fetch(:lock_version), "final lock_version mismatch for #{db_case.name}"
    end
  end

  private

  def build_cases
    adapters = ENV.fetch("HAKUMI_REAL_DB_CONCURRENCY_ADAPTERS", "postgresql,mysql").split(",").map(&:strip).reject(&:empty?)
    cases = []

    adapters.each do |name|
      case name
      when "postgresql"
        database_name = ENV.fetch("HAKUMI_REAL_PG_DB", nil)
        next unless database_name

        cases << build_postgresql_case(database_name)
      when "mysql"
        database_name = ENV.fetch("HAKUMI_REAL_MYSQL_DB", nil)
        next unless database_name

        cases << build_mysql_case(database_name)
      end
    end

    cases
  end

  def build_postgresql_case(database_name)
    require "hakumi_orm/adapter/postgresql"

    params = {
      dbname: database_name,
      user: ENV.fetch("HAKUMI_REAL_PG_USER", nil) || ENV.fetch("PGUSER", nil) || ENV.fetch("USER", nil)
    }
    params[:password] = ENV.fetch("HAKUMI_REAL_PG_PASSWORD", nil) if ENV.fetch("HAKUMI_REAL_PG_PASSWORD", nil)
    params[:host] = ENV.fetch("HAKUMI_REAL_PG_HOST", nil) if ENV.fetch("HAKUMI_REAL_PG_HOST", nil)
    params[:port] = Integer(ENV.fetch("HAKUMI_REAL_PG_PORT", nil)) if ENV.fetch("HAKUMI_REAL_PG_PORT", nil)

    RealDbCase.new(
      name: :postgresql,
      adapter1: HakumiORM::Adapter::Postgresql.connect(params),
      adapter2: HakumiORM::Adapter::Postgresql.connect(params)
    )
  end

  def build_mysql_case(database_name)
    require "hakumi_orm/adapter/mysql"

    params = {
      database: database_name,
      username: ENV.fetch("HAKUMI_REAL_MYSQL_USER", nil) || "root"
    }
    params[:password] = ENV.fetch("HAKUMI_REAL_MYSQL_PASSWORD", nil) if ENV.fetch("HAKUMI_REAL_MYSQL_PASSWORD", nil)
    params[:host] = ENV.fetch("HAKUMI_REAL_MYSQL_HOST", nil) if ENV.fetch("HAKUMI_REAL_MYSQL_HOST", nil)
    params[:port] = Integer(ENV.fetch("HAKUMI_REAL_MYSQL_PORT", nil)) if ENV.fetch("HAKUMI_REAL_MYSQL_PORT", nil)

    RealDbCase.new(
      name: :mysql,
      adapter1: HakumiORM::Adapter::Mysql.connect(params),
      adapter2: HakumiORM::Adapter::Mysql.connect(params)
    )
  end

  def create_locking_table!(db_case)
    adapter = db_case.adapter1
    adapter.exec(%(DROP TABLE IF EXISTS #{quoted_table(db_case)})).close
    adapter.exec(create_locking_table_sql(db_case)).close
  end

  def create_locking_table_sql(db_case)
    case db_case.name
    when :postgresql
      <<~SQL
        CREATE TABLE #{quoted_table(db_case)} (
          #{qcol(db_case, "id")} bigserial PRIMARY KEY,
          #{qcol(db_case, "name")} text NOT NULL,
          #{qcol(db_case, "lock_version")} integer NOT NULL DEFAULT 0
        )
      SQL
    else
      <<~SQL
        CREATE TABLE #{quoted_table(db_case)} (
          #{qcol(db_case, "id")} bigint AUTO_INCREMENT PRIMARY KEY,
          #{qcol(db_case, "name")} text NOT NULL,
          #{qcol(db_case, "lock_version")} int NOT NULL DEFAULT 0
        )
      SQL
    end
  end

  def seed_locking_row!(db_case)
    adapter = db_case.adapter1
    dialect = adapter.dialect
    sql = %(INSERT INTO #{quoted_table(db_case)} (#{qcol(db_case, "name")}, #{qcol(db_case, "lock_version")}) VALUES (#{dialect.bind_marker(0)}, #{dialect.bind_marker(1)}))
    result = adapter.exec_params(sql, [dialect.encode_string("initial"), dialect.encode_integer(0)])
    result.close
  end

  def read_locking_row(db_case, adapter)
    sql = %(SELECT #{qcol(db_case, "id")}, #{qcol(db_case, "name")}, #{qcol(db_case, "lock_version")} FROM #{quoted_table(db_case)} LIMIT 1)
    result = adapter.exec(sql)
    raise "Expected seeded row for #{db_case.name}" if result.row_count.zero?

    {
      id: adapter.dialect.cast_integer(result.fetch_value(0, 0)),
      name: adapter.dialect.cast_string(result.fetch_value(0, 1)),
      lock_version: adapter.dialect.cast_integer(result.fetch_value(0, 2))
    }
  ensure
    result&.close
  end

  def update_with_optimistic_lock(db_case, adapter, name:, expected_lock_version:)
    dialect = adapter.dialect
    sql = %(UPDATE #{quoted_table(db_case)} SET #{qcol(db_case, "name")} = #{dialect.bind_marker(0)}, #{qcol(db_case, "lock_version")} = #{qcol(db_case, "lock_version")} + 1 WHERE #{qcol(db_case, "id")} = #{dialect.bind_marker(1)} AND #{qcol(db_case, "lock_version")} = #{dialect.bind_marker(2)})
    adapter.exec_params(
      sql,
      [
        dialect.encode_string(name),
        dialect.encode_integer(1),
        dialect.encode_integer(expected_lock_version)
      ]
    )
  end

  def quoted_table(db_case)
    db_case.adapter1.dialect.quote_id(TABLE_NAME)
  end

  def qcol(db_case, name)
    db_case.adapter1.dialect.quote_id(name)
  end
end
