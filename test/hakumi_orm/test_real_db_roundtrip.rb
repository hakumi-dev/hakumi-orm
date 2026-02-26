# typed: false
# frozen_string_literal: true

require "test_helper"
require "bigdecimal"
require "date"

class TestRealDbRoundtrip < HakumiORM::TestCase
  RealDbCase = Struct.new(:name, :adapter, :json_type_sql, :time_keeps_usec, keyword_init: true)

  TABLE_NAME = "hakumi_roundtrip_types"

  def setup
    skip "Set HAKUMI_REAL_DB_ROUNDTRIP=1 to run real DB roundtrip tests" unless ENV["HAKUMI_REAL_DB_ROUNDTRIP"] == "1"

    @cases = build_cases
    skip "No real DB adapters configured (set HAKUMI_REAL_DB_ADAPTERS and connection env vars)" if @cases.empty?
  end

  def teardown
    @cases&.each do |db_case|
      begin
        db_case.adapter.exec(%(DROP TABLE IF EXISTS #{quoted_table(db_case)}))&.close
      rescue StandardError
        nil
      end
      db_case.adapter.close
    end
  end

  test "real DB roundtrip matrix for core types across configured adapters" do
    @cases.each do |db_case|
      adapter = db_case.adapter
      dialect = adapter.dialect
      create_roundtrip_table!(db_case)

      expected_time = Time.utc(2026, 2, 26, 12, 34, 56, 123_456)
      expected_date = Date.new(2026, 2, 26)
      expected_decimal = BigDecimal("1234567.890123")
      expected_json = HakumiORM::Json.from_hash({ "name" => "Hakumi", "count" => 3, "active" => true })
      expected_uuid = "550e8400-e29b-41d4-a716-446655440000"

      insert_sql = <<~SQL.strip
        INSERT INTO #{quoted_table(db_case)} (
          #{qcol(db_case, "bool_col")},
          #{qcol(db_case, "int_col")},
          #{qcol(db_case, "bigint_col")},
          #{qcol(db_case, "decimal_col")},
          #{qcol(db_case, "date_col")},
          #{qcol(db_case, "time_col")},
          #{qcol(db_case, "json_col")},
          #{qcol(db_case, "uuid_col")}
        ) VALUES (#{markers(dialect, 8)})
      SQL

      params = [
        dialect.encode_boolean(true),
        dialect.encode_integer(42),
        dialect.encode_integer(9_223_372_036_854_775_000),
        dialect.encode_decimal(expected_decimal),
        dialect.encode_date(expected_date),
        dialect.encode_time(expected_time),
        dialect.encode_json(expected_json),
        dialect.encode_string(expected_uuid)
      ]

      insert_result = adapter.exec_params(insert_sql, params)
      insert_result.close

      select_sql = <<~SQL.strip
        SELECT
          #{qcol(db_case, "bool_col")},
          #{qcol(db_case, "int_col")},
          #{qcol(db_case, "bigint_col")},
          #{qcol(db_case, "decimal_col")},
          #{qcol(db_case, "date_col")},
          #{qcol(db_case, "time_col")},
          #{qcol(db_case, "json_col")},
          #{qcol(db_case, "uuid_col")}
        FROM #{quoted_table(db_case)}
        LIMIT 1
      SQL

      result = adapter.exec(select_sql)

      assert_equal 1, result.row_count, "expected one row for #{db_case.name}"

      assert(dialect.cast_boolean(result.fetch_value(0, 0)), "bool roundtrip failed for #{db_case.name}")
      assert_equal 42, dialect.cast_integer(result.fetch_value(0, 1)), "int roundtrip failed for #{db_case.name}"
      assert_equal 9_223_372_036_854_775_000, dialect.cast_integer(result.fetch_value(0, 2)), "bigint roundtrip failed for #{db_case.name}"
      assert_equal expected_decimal, dialect.cast_decimal(result.fetch_value(0, 3)), "decimal roundtrip failed for #{db_case.name}"
      assert_equal expected_date, dialect.cast_date(result.fetch_value(0, 4)), "date roundtrip failed for #{db_case.name}"

      roundtrip_time = dialect.cast_time(result.fetch_value(0, 5))

      assert_predicate roundtrip_time, :utc?, "time must be UTC for #{db_case.name}"
      assert_equal [2026, 2, 26, 12, 34, 56], [roundtrip_time.year, roundtrip_time.month, roundtrip_time.day, roundtrip_time.hour, roundtrip_time.min, roundtrip_time.sec]
      assert_equal(db_case.time_keeps_usec ? 123_456 : 0, roundtrip_time.usec, "time precision mismatch for #{db_case.name}")

      roundtrip_json = dialect.cast_json(result.fetch_value(0, 6))

      assert_equal "Hakumi", roundtrip_json["name"]&.as_s, "json roundtrip failed for #{db_case.name}"
      assert_equal 3, roundtrip_json["count"]&.as_i, "json roundtrip failed for #{db_case.name}"
      assert(roundtrip_json["active"]&.as_bool, "json roundtrip failed for #{db_case.name}")

      assert_equal expected_uuid, dialect.cast_string(result.fetch_value(0, 7)), "uuid string roundtrip failed for #{db_case.name}"
    ensure
      result&.close
    end
  end

  private

  def build_cases
    adapters = ENV.fetch("HAKUMI_REAL_DB_ADAPTERS", "sqlite").split(",").map(&:strip).reject(&:empty?)
    cases = []

    adapters.each do |name|
      case name
      when "postgresql"
        db = ENV.fetch("HAKUMI_REAL_PG_DB", nil)
        next unless db

        cases << build_postgresql_case(db)
      when "mysql"
        db = ENV.fetch("HAKUMI_REAL_MYSQL_DB", nil)
        next unless db

        cases << build_mysql_case(db)
      when "sqlite"
        cases << build_sqlite_case
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
    adapter = HakumiORM::Adapter::Postgresql.connect(params)
    RealDbCase.new(name: :postgresql, adapter: adapter, json_type_sql: "jsonb", time_keeps_usec: true)
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
    adapter = HakumiORM::Adapter::Mysql.connect(params)
    RealDbCase.new(name: :mysql, adapter: adapter, json_type_sql: "json", time_keeps_usec: true)
  end

  def build_sqlite_case
    require "hakumi_orm/adapter/sqlite"

    path = ENV.fetch("HAKUMI_REAL_SQLITE_PATH", nil) || "/tmp/hakumi_orm_real_roundtrip.sqlite3"
    adapter = HakumiORM::Adapter::Sqlite.connect(path)
    RealDbCase.new(name: :sqlite, adapter: adapter, json_type_sql: "TEXT", time_keeps_usec: false)
  end

  def create_roundtrip_table!(db_case)
    adapter = db_case.adapter
    adapter.exec(%(DROP TABLE IF EXISTS #{quoted_table(db_case)})).close

    create_sql = create_roundtrip_table_sql(db_case)

    adapter.exec(create_sql).close
  end

  def create_roundtrip_table_sql(db_case)
    case db_case.name
    when :postgresql then create_roundtrip_table_sql_postgresql(db_case)
    when :mysql then create_roundtrip_table_sql_mysql(db_case)
    else create_roundtrip_table_sql_sqlite(db_case)
    end
  end

  def create_roundtrip_table_sql_postgresql(db_case)
    <<~SQL
      CREATE TABLE #{quoted_table(db_case)} (
        #{qcol(db_case, "id")} bigserial PRIMARY KEY,
        #{qcol(db_case, "bool_col")} boolean NOT NULL,
        #{qcol(db_case, "int_col")} integer NOT NULL,
        #{qcol(db_case, "bigint_col")} bigint NOT NULL,
        #{qcol(db_case, "decimal_col")} numeric(18,6) NOT NULL,
        #{qcol(db_case, "date_col")} date NOT NULL,
        #{qcol(db_case, "time_col")} timestamp NOT NULL,
        #{qcol(db_case, "json_col")} #{db_case.json_type_sql} NOT NULL,
        #{qcol(db_case, "uuid_col")} uuid NOT NULL
      )
    SQL
  end

  def create_roundtrip_table_sql_mysql(db_case)
    <<~SQL
      CREATE TABLE #{quoted_table(db_case)} (
        #{qcol(db_case, "id")} bigint AUTO_INCREMENT PRIMARY KEY,
        #{qcol(db_case, "bool_col")} tinyint(1) NOT NULL,
        #{qcol(db_case, "int_col")} int NOT NULL,
        #{qcol(db_case, "bigint_col")} bigint NOT NULL,
        #{qcol(db_case, "decimal_col")} decimal(18,6) NOT NULL,
        #{qcol(db_case, "date_col")} date NOT NULL,
        #{qcol(db_case, "time_col")} datetime(6) NOT NULL,
        #{qcol(db_case, "json_col")} #{db_case.json_type_sql} NOT NULL,
        #{qcol(db_case, "uuid_col")} char(36) NOT NULL
      )
    SQL
  end

  def create_roundtrip_table_sql_sqlite(db_case)
    <<~SQL
      CREATE TABLE #{quoted_table(db_case)} (
        #{qcol(db_case, "id")} INTEGER PRIMARY KEY AUTOINCREMENT,
        #{qcol(db_case, "bool_col")} BOOLEAN NOT NULL,
        #{qcol(db_case, "int_col")} INTEGER NOT NULL,
        #{qcol(db_case, "bigint_col")} INTEGER NOT NULL,
        #{qcol(db_case, "decimal_col")} NUMERIC NOT NULL,
        #{qcol(db_case, "date_col")} DATE NOT NULL,
        #{qcol(db_case, "time_col")} DATETIME NOT NULL,
        #{qcol(db_case, "json_col")} #{db_case.json_type_sql} NOT NULL,
        #{qcol(db_case, "uuid_col")} TEXT NOT NULL
      )
    SQL
  end

  def quoted_table(db_case)
    db_case.adapter.dialect.quote_id(TABLE_NAME)
  end

  def qcol(db_case, name)
    db_case.adapter.dialect.quote_id(name)
  end

  def markers(dialect, count)
    (0...count).map { |i| dialect.bind_marker(i) }.join(", ")
  end
end
