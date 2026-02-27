# typed: strict
# frozen_string_literal: true

# Internal component for database_config_builder.
module HakumiORM
  # Internal class for HakumiORM.
  class DatabaseConfigBuilder
    extend T::Sig

    sig { returns(Symbol) }
    attr_accessor :adapter_name

    sig { returns(T.nilable(String)) }
    attr_accessor :database

    sig { returns(T.nilable(String)) }
    attr_accessor :host

    sig { returns(T.nilable(Integer)) }
    attr_accessor :port

    sig { returns(T.nilable(String)) }
    attr_accessor :username

    sig { returns(T.nilable(String)) }
    attr_accessor :password

    sig { returns(Integer) }
    attr_accessor :pool_size

    sig { returns(Float) }
    attr_accessor :pool_timeout

    sig { returns(T::Hash[String, String]) }
    attr_accessor :connection_options

    sig { void }
    def initialize
      @adapter_name = T.let(:postgresql, Symbol)
      @database = T.let(nil, T.nilable(String))
      @host = T.let(nil, T.nilable(String))
      @port = T.let(nil, T.nilable(Integer))
      @username = T.let(nil, T.nilable(String))
      @password = T.let(nil, T.nilable(String))
      @pool_size = T.let(5, Integer)
      @pool_timeout = T.let(5.0, Float)
      @connection_options = T.let({}, T::Hash[String, String])
    end

    sig { params(url: String).void }
    def database_url=(url)
      parsed = DatabaseUrlParser.parse(url)
      @adapter_name = parsed.adapter_name
      @database = parsed.database
      @host = parsed.host
      @port = parsed.port
      @username = parsed.username
      @password = parsed.password
      @connection_options = parsed.connection_options
    end

    sig { returns(DatabaseConfig) }
    def build
      db = @database
      raise HakumiORM::Error, "database_config requires a 'database' to be set" unless db

      unless Configuration::SUPPORTED_ADAPTERS.include?(@adapter_name)
        raise HakumiORM::Error,
              "Unknown adapter_name: #{@adapter_name.inspect}. Supported: " \
              "#{Configuration::SUPPORTED_ADAPTERS.map(&:inspect).join(", ")}"
      end

      DatabaseConfig.new(
        adapter_name: @adapter_name,
        database: db,
        host: @host,
        port: @port,
        username: @username,
        password: @password,
        pool_size: @pool_size,
        pool_timeout: @pool_timeout,
        connection_options: @connection_options
      )
    end
  end
end
