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

    sig { void }
    def initialize
      @adapter = T.let(nil, T.nilable(Adapter::Base))
      @adapter_name = T.let(:postgresql, Symbol)
      @database = T.let(nil, T.nilable(String))
      @host = T.let(nil, T.nilable(String))
      @port = T.let(nil, T.nilable(Integer))
      @username = T.let(nil, T.nilable(String))
      @password = T.let(nil, T.nilable(String))
      @output_dir = T.let("app/db/generated", String)
      @models_dir = T.let(nil, T.nilable(String))
      @contracts_dir = T.let(nil, T.nilable(String))
      @module_name = T.let(nil, T.nilable(String))
      @pool_size = T.let(5, Integer)
      @pool_timeout = T.let(5.0, Float)
    end

    sig { params(adapter: T.nilable(Adapter::Base)).void }
    attr_writer :adapter

    sig { returns(T.nilable(Adapter::Base)) }
    def adapter
      @adapter ||= build_adapter
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

      @adapter = connect_adapter(@adapter_name, database)
    end

    sig { params(name: Symbol, database: String).returns(Adapter::Base) }
    def connect_adapter(name, database)
      case name
      when :postgresql
        require_relative "adapter/postgresql"
        Adapter::Postgresql.connect(build_connection_params(database))
      when :mysql
        require_relative "adapter/mysql"
        Adapter::Mysql.connect(build_mysql_params(database))
      when :sqlite
        require_relative "adapter/sqlite"
        Adapter::Sqlite.connect(database)
      else
        raise HakumiORM::Error, "Adapter #{name.inspect} is not yet implemented"
      end
    end

    sig { params(database: String).returns(T::Hash[Symbol, T.any(String, Integer)]) }
    def build_connection_params(database)
      params = T.let({ dbname: database }, T::Hash[Symbol, T.any(String, Integer)])
      h = @host
      params[:host] = h if h
      p = @port
      params[:port] = p if p
      u = @username
      params[:user] = u if u
      pw = @password
      params[:password] = pw if pw
      params
    end

    sig { params(database: String).returns(T::Hash[Symbol, T.any(String, Integer)]) }
    def build_mysql_params(database)
      params = T.let({ database: database }, T::Hash[Symbol, T.any(String, Integer)])
      h = @host
      params[:host] = h if h
      p = @port
      params[:port] = p if p
      u = @username
      params[:username] = u if u
      pw = @password
      params[:password] = pw if pw
      params
    end
  end
end
