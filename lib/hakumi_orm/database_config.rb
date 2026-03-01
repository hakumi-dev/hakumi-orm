# typed: strict
# frozen_string_literal: true

# Internal component for database_config.
module HakumiORM
  # Internal class for HakumiORM.
  class DatabaseConfig
    extend T::Sig

    sig { returns(Symbol) }
    attr_reader :adapter_name

    sig { returns(String) }
    attr_reader :database

    sig { returns(T.nilable(String)) }
    attr_reader :host

    sig { returns(T.nilable(Integer)) }
    attr_reader :port

    sig { returns(T.nilable(String)) }
    attr_reader :username

    sig { returns(T.nilable(String)) }
    attr_reader :password

    sig { returns(Integer) }
    attr_reader :pool_size

    sig { returns(Float) }
    attr_reader :pool_timeout

    sig { returns(T::Hash[String, String]) }
    attr_reader :connection_options

    sig do
      params(
        adapter_name: Symbol,
        database: String,
        host: T.nilable(String),
        port: T.nilable(Integer),
        username: T.nilable(String),
        password: T.nilable(String),
        pool_size: Integer,
        pool_timeout: Float,
        connection_options: T::Hash[String, String]
      ).void
    end
    def initialize(
      adapter_name:,
      database:,
      host: nil,
      port: nil,
      username: nil,
      password: nil,
      pool_size: 5,
      pool_timeout: 5.0,
      connection_options: {}
    )
      @adapter_name = T.let(adapter_name, Symbol)
      @database = T.let(database, String)
      @host = T.let(host, T.nilable(String))
      @port = T.let(port, T.nilable(Integer))
      @username = T.let(username, T.nilable(String))
      @password = T.let(password, T.nilable(String))
      @pool_size = T.let(pool_size, Integer)
      @pool_timeout = T.let(pool_timeout, Float)
      @connection_options = T.let(connection_options.dup.freeze, T::Hash[String, String])
    end
  end
end
