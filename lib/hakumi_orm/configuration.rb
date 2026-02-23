# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Configuration
    extend T::Sig

    SUPPORTED_ADAPTERS = T.let(%i[postgresql mysql sqlite].freeze, T::Array[Symbol])

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

    sig { returns(String) }
    attr_accessor :output_dir

    sig { returns(T.nilable(String)) }
    attr_accessor :models_dir

    sig { returns(T.nilable(String)) }
    attr_accessor :contracts_dir

    sig { returns(T.nilable(String)) }
    attr_accessor :module_name

    sig { returns(Integer) }
    attr_accessor :pool_size

    sig { returns(Float) }
    attr_accessor :pool_timeout

    sig { returns(T.nilable(Loggable)) }
    attr_accessor :logger

    sig { returns(String) }
    attr_accessor :migrations_path

    sig { returns(String) }
    attr_accessor :associations_path

    sig { returns(String) }
    attr_accessor :enums_path

    sig { returns(T.nilable(String)) }
    attr_accessor :schema_fingerprint

    sig { returns(T::Hash[String, String]) }
    attr_accessor :connection_options

    sig { void }
    def initialize # rubocop:disable Metrics/AbcSize
      @adapter = T.let(nil, T.nilable(Adapter::Base))
      @adapter_name = T.let(:postgresql, Symbol)
      @database = T.let(nil, T.nilable(String))
      @host = T.let(nil, T.nilable(String))
      @port = T.let(nil, T.nilable(Integer))
      @username = T.let(nil, T.nilable(String))
      @password = T.let(nil, T.nilable(String))
      @output_dir = T.let("db/generated", String)
      @models_dir = T.let(nil, T.nilable(String))
      @contracts_dir = T.let(nil, T.nilable(String))
      @module_name = T.let(nil, T.nilable(String))
      @pool_size = T.let(5, Integer)
      @pool_timeout = T.let(5.0, Float)
      @logger = T.let(nil, T.nilable(Loggable))
      @migrations_path = T.let("db/migrate", String)
      @associations_path = T.let("db/associations", String)
      @enums_path = T.let("db/enums", String)
      @schema_fingerprint = T.let(nil, T.nilable(String))
      @connection_options = T.let({}, T::Hash[String, String])
      @named_databases = T.let({}, T::Hash[Symbol, DatabaseConfig])
      @named_adapters = T.let({}, T::Hash[Symbol, Adapter::Base])
    end

    LOG_LEVELS = T.let({
      debug: ::Logger::DEBUG,
      info: ::Logger::INFO,
      warn: ::Logger::WARN,
      error: ::Logger::ERROR,
      fatal: ::Logger::FATAL
    }.freeze, T::Hash[Symbol, Integer])

    sig { params(level: Symbol).void }
    def log_level=(level)
      valid_levels = LOG_LEVELS.keys
      numeric = LOG_LEVELS.fetch(level) do
        raise ArgumentError, "Invalid log level: #{level.inspect}. Use: #{valid_levels.join(", ")}"
      end
      stdlib_logger = ::Logger.new($stdout)
      stdlib_logger.level = numeric
      @logger = stdlib_logger
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

    sig { params(adapter: T.nilable(Adapter::Base)).void }
    attr_writer :adapter

    sig { returns(T.nilable(Adapter::Base)) }
    def adapter
      @adapter ||= build_adapter
    end

    sig { params(name: Symbol, blk: T.proc.params(builder: DatabaseConfigBuilder).void).void }
    def database_config(name, &blk)
      raise HakumiORM::Error, "Database name :primary is reserved for the main database" if name == :primary
      raise HakumiORM::Error, "Database '#{name}' is already registered" if @named_databases.key?(name)

      builder = DatabaseConfigBuilder.new
      blk.call(builder)
      @named_databases[name] = builder.build
    end

    sig { params(name: Symbol).returns(DatabaseConfig) }
    def named_database(name)
      config = @named_databases[name]
      raise HakumiORM::Error, "Database '#{name}' is not registered. Available: #{@named_databases.keys.inspect}" unless config

      config
    end

    sig { params(name: Symbol, adapter: Adapter::Base).void }
    def register_adapter(name, adapter)
      @named_adapters[name] = adapter
    end

    sig { params(name: Symbol).returns(Adapter::Base) }
    def adapter_for(name)
      if name == :primary
        primary = adapter
        raise HakumiORM::Error, "No primary adapter configured" unless primary

        return primary
      end

      existing = @named_adapters[name]
      return existing if existing

      db_config = named_database(name)
      built = connect_from_config(db_config)
      @named_adapters[name] = built
      built
    end

    sig { returns(T::Array[Symbol]) }
    def database_names
      @named_databases.keys
    end

    sig { void }
    def close_named_adapters!
      @named_adapters.each_value(&:close)
      @named_adapters.clear
    end

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

    sig { params(adapter: Adapter::Base).void }
    def verify_schema_fingerprint!(adapter)
      expected = @schema_fingerprint
      return unless expected

      actual = Migration::SchemaFingerprint.read_from_db(adapter)
      return unless actual

      Migration::SchemaFingerprint.check!(expected, actual)
    end

    sig { params(adapter: Adapter::Base).void }
    def verify_no_pending_migrations!(adapter)
      return unless @schema_fingerprint

      pending = Migration::SchemaFingerprint.pending_migrations(adapter, @migrations_path)
      return if pending.empty?

      raise PendingMigrationError, pending
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
