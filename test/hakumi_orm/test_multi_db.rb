# typed: false
# frozen_string_literal: true

require "test_helper"

class TestMultiDb < HakumiORM::TestCase
  def setup
    HakumiORM.reset_config!
    HakumiORM.configure do |c|
      c.adapter_name = :postgresql
      c.database = "primary_db"
    end
  end

  def teardown
    HakumiORM.reset_config!
  end

  test "DatabaseConfig stores connection parameters" do
    dc = HakumiORM::DatabaseConfig.new(
      adapter_name: :postgresql,
      database: "replica_db",
      host: "replica.host",
      port: 5433,
      username: "readonly",
      password: "secret",
      pool_size: 3,
      pool_timeout: 2.0
    )

    assert_equal :postgresql, dc.adapter_name
    assert_equal "replica_db", dc.database
    assert_equal "replica.host", dc.host
    assert_equal 5433, dc.port
    assert_equal "readonly", dc.username
    assert_equal "secret", dc.password
    assert_equal 3, dc.pool_size
    assert_in_delta 2.0, dc.pool_timeout
  end

  test "DatabaseConfig has sensible defaults" do
    dc = HakumiORM::DatabaseConfig.new(
      adapter_name: :postgresql,
      database: "test_db"
    )

    assert_nil dc.host
    assert_nil dc.port
    assert_nil dc.username
    assert_nil dc.password
    assert_equal 5, dc.pool_size
    assert_in_delta 5.0, dc.pool_timeout
  end

  test "database_config registers a named database" do
    HakumiORM.configure do |c|
      c.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "replica_db"
        r.host = "replica.host"
      end
    end

    config = HakumiORM.config.named_database(:replica)

    assert_equal :postgresql, config.adapter_name
    assert_equal "replica_db", config.database
    assert_equal "replica.host", config.host
  end

  test "database_config raises on duplicate name" do
    HakumiORM.configure do |c|
      c.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "replica_db"
      end
    end

    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "other_db"
      end
    end

    assert_includes error.message, "replica"
    assert_includes error.message, "already registered"
  end

  test "database_config raises on :primary name" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.database_config(:primary) do |r|
        r.adapter_name = :postgresql
        r.database = "other_db"
      end
    end

    assert_includes error.message, "primary"
    assert_includes error.message, "reserved"
  end

  test "named_database raises for unknown name" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.named_database(:nonexistent)
    end

    assert_includes error.message, "nonexistent"
    assert_includes error.message, "not registered"
  end

  test "adapter with name returns the named adapter" do
    mock = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = mock

    replica_mock = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Mysql.new)
    HakumiORM.config.register_adapter(:replica, replica_mock)

    adapter = HakumiORM.adapter(:replica)

    assert_same replica_mock, adapter
  end

  test "adapter without name returns primary" do
    mock = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = mock

    assert_same mock, HakumiORM.adapter
  end

  test "using switches adapter for the block" do
    primary = HakumiORM::Test::MockAdapter.new
    replica = HakumiORM::Test::MockAdapter.new(dialect: HakumiORM::Dialect::Mysql.new)
    HakumiORM.config.adapter = primary
    HakumiORM.config.register_adapter(:replica, replica)

    adapter_inside = nil
    HakumiORM.using(:replica) do
      adapter_inside = HakumiORM.adapter
    end

    assert_same replica, adapter_inside
    assert_same primary, HakumiORM.adapter
  end

  test "using restores adapter after exception" do
    primary = HakumiORM::Test::MockAdapter.new
    replica = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = primary
    HakumiORM.config.register_adapter(:replica, replica)

    begin
      HakumiORM.using(:replica) do
        raise "boom"
      end
    rescue RuntimeError
      nil
    end

    assert_same primary, HakumiORM.adapter
  end

  test "using is nestable" do
    primary = HakumiORM::Test::MockAdapter.new
    replica = HakumiORM::Test::MockAdapter.new
    analytics = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = primary
    HakumiORM.config.register_adapter(:replica, replica)
    HakumiORM.config.register_adapter(:analytics, analytics)

    adapters = []
    HakumiORM.using(:replica) do
      adapters << HakumiORM.adapter
      HakumiORM.using(:analytics) do
        adapters << HakumiORM.adapter
      end
      adapters << HakumiORM.adapter
    end
    adapters << HakumiORM.adapter

    assert_same replica, adapters[0]
    assert_same analytics, adapters[1]
    assert_same replica, adapters[2]
    assert_same primary, adapters[3]
  end

  test "using raises for unknown database name" do
    primary = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = primary

    error = assert_raises(HakumiORM::Error) do
      HakumiORM.using(:nonexistent) do
        HakumiORM.adapter
      end
    end

    assert_includes error.message, "nonexistent"
  end

  test "reset_config clears named databases" do
    HakumiORM.configure do |c|
      c.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "replica_db"
      end
    end

    HakumiORM.reset_config!

    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.named_database(:replica)
    end

    assert_includes error.message, "not registered"
  end

  test "database_names returns all registered names" do
    HakumiORM.configure do |c|
      c.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "replica_db"
      end

      c.database_config(:analytics) do |r|
        r.adapter_name = :postgresql
        r.database = "analytics_db"
      end
    end

    names = HakumiORM.config.database_names

    assert_includes names, :replica
    assert_includes names, :analytics
    assert_equal 2, names.length
  end

  test "using with primary name returns primary adapter" do
    primary = HakumiORM::Test::MockAdapter.new
    HakumiORM.config.adapter = primary

    adapter_inside = nil
    HakumiORM.using(:primary) do
      adapter_inside = HakumiORM.adapter
    end

    assert_same primary, adapter_inside
  end

  test "pg_params uses named database config, not primary" do
    HakumiORM.configure do |c|
      c.host = "primary.host"
      c.username = "primary_user"
      c.password = "primary_pw"
      c.port = 5432

      c.database_config(:replica) do |r|
        r.adapter_name = :postgresql
        r.database = "replica_db"
        r.host = "replica.host"
        r.username = "replica_user"
        r.password = "replica_pw"
        r.port = 5433
      end
    end

    db_config = HakumiORM.config.named_database(:replica)
    params = HakumiORM.config.send(:pg_params, db_config)

    assert_equal "replica_db", params[:dbname]
    assert_equal "replica.host", params[:host]
    assert_equal "replica_user", params[:user]
    assert_equal "replica_pw", params[:password]
    assert_equal 5433, params[:port]
  end

  test "mysql_params uses named database config, not primary" do
    HakumiORM.configure do |c|
      c.host = "primary.host"
      c.username = "primary_user"

      c.database_config(:replica) do |r|
        r.adapter_name = :mysql
        r.database = "replica_db"
        r.host = "replica.host"
        r.username = "replica_user"
        r.password = "replica_pw"
      end
    end

    db_config = HakumiORM.config.named_database(:replica)
    params = HakumiORM.config.send(:mysql_params, db_config)

    assert_equal "replica_db", params[:database]
    assert_equal "replica.host", params[:host]
    assert_equal "replica_user", params[:username]
    assert_equal "replica_pw", params[:password]
  end

  test "pg_params omits nil optional fields" do
    HakumiORM.configure do |c|
      c.database_config(:minimal) do |r|
        r.adapter_name = :postgresql
        r.database = "minimal_db"
      end
    end

    db_config = HakumiORM.config.named_database(:minimal)
    params = HakumiORM.config.send(:pg_params, db_config)

    assert_equal({ dbname: "minimal_db" }, params)
  end

  test "database_url parses postgresql URL into config fields" do
    HakumiORM.configure do |c|
      c.database_url = "postgresql://app_user:s3cret@db.host.com:5433/myapp_prod"
    end

    cfg = HakumiORM.config

    assert_equal :postgresql, cfg.adapter_name
    assert_equal "myapp_prod", cfg.database
    assert_equal "db.host.com", cfg.host
    assert_equal 5433, cfg.port
    assert_equal "app_user", cfg.username
    assert_equal "s3cret", cfg.password
  end

  test "database_url parses postgres:// scheme" do
    HakumiORM.configure do |c|
      c.database_url = "postgres://user@host/db"
    end

    assert_equal :postgresql, HakumiORM.config.adapter_name
    assert_equal "db", HakumiORM.config.database
  end

  test "database_url parses mysql2 URL" do
    HakumiORM.configure do |c|
      c.database_url = "mysql2://root:pw@mysql.host:3307/myapp"
    end

    cfg = HakumiORM.config

    assert_equal :mysql, cfg.adapter_name
    assert_equal "myapp", cfg.database
    assert_equal "mysql.host", cfg.host
    assert_equal 3307, cfg.port
    assert_equal "root", cfg.username
    assert_equal "pw", cfg.password
  end

  test "database_url parses mysql:// scheme" do
    HakumiORM.configure do |c|
      c.database_url = "mysql://root@localhost/myapp"
    end

    assert_equal :mysql, HakumiORM.config.adapter_name
  end

  test "database_url parses sqlite3 URL" do
    HakumiORM.configure do |c|
      c.database_url = "sqlite3:///path/to/db.sqlite3"
    end

    cfg = HakumiORM.config

    assert_equal :sqlite, cfg.adapter_name
    assert_equal "/path/to/db.sqlite3", cfg.database
  end

  test "database_url parses sqlite:// scheme" do
    HakumiORM.configure do |c|
      c.database_url = "sqlite:///tmp/test.db"
    end

    assert_equal :sqlite, HakumiORM.config.adapter_name
    assert_equal "/tmp/test.db", HakumiORM.config.database
  end

  test "database_url decodes percent-encoded password" do
    HakumiORM.configure do |c|
      c.database_url = "postgresql://user:p%40ss%23word@host/db"
    end

    assert_equal "p@ss#word", HakumiORM.config.password
  end

  test "database_url with query params stores them as connection_options" do
    HakumiORM.configure do |c|
      c.database_url = "postgresql://user@host/db?sslmode=require&connect_timeout=10"
    end

    opts = HakumiORM.config.connection_options

    assert_equal "require", opts["sslmode"]
    assert_equal "10", opts["connect_timeout"]
  end

  test "database_url raises on unsupported scheme" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.configure do |c|
        c.database_url = "mongodb://host/db"
      end
    end

    assert_includes error.message, "mongodb"
  end

  test "database_url raises on invalid URL" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.configure do |c|
        c.database_url = "not a url"
      end
    end

    assert_includes error.message, "Invalid database_url"
  end

  test "database_url works on named database builder" do
    HakumiORM.configure do |c|
      c.adapter_name = :postgresql
      c.database = "primary_db"

      c.database_config(:replica) do |r|
        r.database_url = "postgresql://ro_user:ro_pass@replica.host:5434/replica_db?sslmode=verify-full"
      end
    end

    db_config = HakumiORM.config.named_database(:replica)

    assert_equal :postgresql, db_config.adapter_name
    assert_equal "replica_db", db_config.database
    assert_equal "replica.host", db_config.host
    assert_equal 5434, db_config.port
    assert_equal "ro_user", db_config.username
    assert_equal "ro_pass", db_config.password
    assert_equal({ "sslmode" => "verify-full" }, db_config.connection_options)
  end

  test "pg_params includes connection_options" do
    HakumiORM.configure do |c|
      c.database_config(:secure) do |r|
        r.database_url = "postgresql://user:pw@host/db?sslmode=require&connect_timeout=5"
      end
    end

    db_config = HakumiORM.config.named_database(:secure)
    params = HakumiORM.config.send(:pg_params, db_config)

    assert_equal "require", params[:sslmode]
    assert_equal "5", params[:connect_timeout]
  end

  test "mysql_params includes connection_options as symbols" do
    HakumiORM.configure do |c|
      c.database_config(:secure) do |r|
        r.database_url = "mysql2://user:pw@host/db?ssl_mode=required"
      end
    end

    db_config = HakumiORM.config.named_database(:secure)
    params = HakumiORM.config.send(:mysql_params, db_config)

    assert_equal "required", params[:ssl_mode]
  end

  test "connection_options defaults to empty hash" do
    assert_empty HakumiORM.config.connection_options
  end

  test "database_config validates adapter_name" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.database_config(:replica) do |r|
        r.adapter_name = :mongodb
        r.database = "replica_db"
      end
    end

    assert_includes error.message, "mongodb"
    assert_includes error.message, "Supported"
  end

  test "database_config requires database" do
    error = assert_raises(HakumiORM::Error) do
      HakumiORM.config.database_config(:replica) do |r|
        r.adapter_name = :postgresql
      end
    end

    assert_includes error.message, "database"
  end
end
