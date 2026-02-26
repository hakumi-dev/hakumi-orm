# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Configuration methods that build and connect adapters from config data.
  class Configuration
    extend T::Sig

    private

    sig { returns(T.nilable(Adapter::Base)) }
    def build_adapter
      database = @database
      return nil unless database

      unless SUPPORTED_ADAPTERS.include?(@adapter_name)
        raise HakumiORM::Error,
              "Unknown adapter_name: #{@adapter_name.inspect}. Supported: #{SUPPORTED_ADAPTERS.map(&:inspect).join(", ")}"
      end

      new_adapter = connect_from_config(primary_database_config(database))
      verify_schema_fingerprint!(new_adapter)
      verify_no_pending_migrations!(new_adapter)
      @adapter = new_adapter
    end

    sig { params(database: String).returns(DatabaseConfig) }
    def primary_database_config(database)
      DatabaseConfig.new(
        adapter_name: @adapter_name,
        database: database,
        host: @host,
        port: @port,
        username: @username,
        password: @password,
        pool_size: @pool_size,
        pool_timeout: @pool_timeout,
        connection_options: @connection_options
      )
    end

    sig { params(db_config: DatabaseConfig).returns(Adapter::Base) }
    def connect_from_config(db_config)
      case db_config.adapter_name
      when :postgresql
        require_relative "adapter/postgresql_result"
        require_relative "adapter/postgresql"
        Adapter::Postgresql.connect(pg_params(db_config))
      when :mysql
        require_relative "adapter/mysql_result"
        require_relative "adapter/mysql"
        Adapter::Mysql.connect(mysql_params(db_config))
      when :sqlite
        require_relative "adapter/sqlite_result"
        require_relative "adapter/sqlite"
        Adapter::Sqlite.connect(db_config.database)
      else
        raise HakumiORM::Error, "Adapter #{db_config.adapter_name.inspect} is not yet implemented"
      end
    end

    sig { params(db_config: DatabaseConfig).returns(T::Hash[Symbol, T.any(String, Integer)]) }
    def pg_params(db_config)
      params = T.let({ dbname: db_config.database }, T::Hash[Symbol, T.any(String, Integer)])
      h = db_config.host
      params[:host] = h if h
      p = db_config.port
      params[:port] = p if p
      u = db_config.username
      params[:user] = u if u
      pw = db_config.password
      params[:password] = pw if pw
      db_config.connection_options.each { |k, v| params[k.to_sym] = v }
      params
    end

    sig { params(db_config: DatabaseConfig).returns(T::Hash[Symbol, T.any(String, Integer)]) }
    def mysql_params(db_config)
      params = T.let({ database: db_config.database }, T::Hash[Symbol, T.any(String, Integer)])
      h = db_config.host
      params[:host] = h if h
      p = db_config.port
      params[:port] = p if p
      u = db_config.username
      params[:username] = u if u
      pw = db_config.password
      params[:password] = pw if pw
      db_config.connection_options.each { |k, v| params[k.to_sym] = v }
      params
    end
  end
end
