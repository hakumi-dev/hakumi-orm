# typed: strict
# frozen_string_literal: true

require_relative "migration/schema_fingerprint"

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

    sig { returns(T::Boolean) }
    attr_accessor :pretty_sql_logs

    sig { returns(T::Boolean) }
    attr_accessor :colorize_sql_logs

    sig { returns(T::Array[String]) }
    attr_accessor :log_filter_parameters

    sig { returns(String) }
    attr_accessor :log_filter_mask

    sig { returns(String) }
    attr_accessor :migrations_path

    sig { returns(String) }
    attr_accessor :definitions_path

    sig { returns(String) }
    attr_accessor :seeds_path

    sig { returns(T.nilable(String)) }
    attr_accessor :schema_fingerprint

    sig { returns(T::Hash[String, String]) }
    attr_accessor :connection_options

    sig { returns(FormModelAdapter) }
    attr_reader :form_model_adapter

    sig { void }
    def initialize
      @adapter = T.let(nil, T.nilable(Adapter::Base))
      @adapter_name = T.let(:postgresql, Symbol)
      @database = T.let(nil, T.nilable(String))
      @host = T.let(nil, T.nilable(String))
      @port = T.let(nil, T.nilable(Integer))
      @username = T.let(nil, T.nilable(String))
      @password = T.let(nil, T.nilable(String))
      @output_dir = T.let("db/schema", String)
      @models_dir = T.let(nil, T.nilable(String))
      @contracts_dir = T.let(nil, T.nilable(String))
      @module_name = T.let(nil, T.nilable(String))
      @pool_size = T.let(5, Integer)
      @pool_timeout = T.let(5.0, Float)
      @logger = T.let(nil, T.nilable(Loggable))
      @pretty_sql_logs = T.let(false, T::Boolean)
      @colorize_sql_logs = T.let(true, T::Boolean)
      @log_filter_parameters = T.let(
        %w[passw email secret token _key crypt salt certificate otp ssn cvv cvc],
        T::Array[String]
      )
      @log_filter_mask = T.let("[FILTERED]", String)
      @migrations_path = T.let("db/migrate", String)
      @definitions_path = T.let("db/definitions.rb", String)
      @seeds_path = T.let("db/seeds.rb", String)
      @schema_fingerprint = T.let(nil, T.nilable(String))
      @connection_options = T.let({}, T::Hash[String, String])
      @form_model_adapter = T.let(HakumiORM::FormModel::NoopAdapter, FormModelAdapter)
      connect_adapter = T.let(
        ->(db_config) { connect_from_config(db_config) },
        T.proc.params(db_config: DatabaseConfig).returns(Adapter::Base)
      )
      primary_adapter = T.let(
        -> { adapter },
        T.proc.returns(T.nilable(Adapter::Base))
      )
      @adapter_registry = T.let(
        AdapterRegistry.new(connect_adapter: connect_adapter, primary_adapter: primary_adapter),
        AdapterRegistry
      )
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

    sig { params(adapter: FormModelAdapter).void }
    def form_model_adapter=(adapter)
      adapter_module = T.cast(adapter, Module)
      raise ArgumentError, "form_model_adapter must define instance method 'to_model'" unless adapter_module.method_defined?(:to_model)

      @form_model_adapter = adapter
    end

    sig { params(adapter: T.nilable(Adapter::Base)).void }
    attr_writer :adapter

    sig { returns(T.nilable(Adapter::Base)) }
    def adapter
      @adapter ||= build_adapter
    end

    sig { params(name: Symbol, blk: T.proc.params(builder: DatabaseConfigBuilder).void).void }
    def database_config(name, &blk)
      builder = DatabaseConfigBuilder.new
      blk.call(builder)
      @adapter_registry.register_database(name, builder.build)
    end

    sig { params(name: Symbol).returns(DatabaseConfig) }
    def named_database(name)
      @adapter_registry.named_database(name)
    end

    sig { params(name: Symbol, adapter: Adapter::Base).void }
    def register_adapter(name, adapter)
      @adapter_registry.register_adapter(name, adapter)
    end

    sig { params(name: Symbol).returns(Adapter::Base) }
    def adapter_for(name)
      @adapter_registry.adapter_for(name)
    end

    sig { returns(T::Array[Symbol]) }
    def database_names
      @adapter_registry.database_names
    end

    sig { void }
    def close_named_adapters!
      @adapter_registry.close_named_adapters!
    end
  end
end
