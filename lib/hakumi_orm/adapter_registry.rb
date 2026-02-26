# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Stores named database configs and manages lazily built named adapters.
  class AdapterRegistry
    extend T::Sig

    sig do
      params(
        connect_adapter: T.proc.params(db_config: DatabaseConfig).returns(Adapter::Base),
        primary_adapter: T.proc.returns(T.nilable(Adapter::Base))
      ).void
    end
    def initialize(connect_adapter:, primary_adapter:)
      @connect_adapter = connect_adapter
      @primary_adapter = primary_adapter
      @named_databases = T.let({}, T::Hash[Symbol, DatabaseConfig])
      @named_adapters = T.let({}, T::Hash[Symbol, Adapter::Base])
    end

    sig { params(name: Symbol, db_config: DatabaseConfig).void }
    def register_database(name, db_config)
      raise HakumiORM::Error, "Database name :primary is reserved for the main database" if name == :primary
      raise HakumiORM::Error, "Database '#{name}' is already registered" if @named_databases.key?(name)

      @named_databases[name] = db_config
    end

    sig { params(name: Symbol).returns(DatabaseConfig) }
    def named_database(name)
      config = @named_databases[name]
      raise HakumiORM::Error, "Database '#{name}' is not registered. Available: #{@named_databases.keys.inspect}" unless config

      config
    end

    sig { returns(T::Array[Symbol]) }
    def database_names
      @named_databases.keys
    end

    sig { params(name: Symbol, adapter: Adapter::Base).void }
    def register_adapter(name, adapter)
      @named_adapters[name] = adapter
    end

    sig { params(name: Symbol).returns(Adapter::Base) }
    def adapter_for(name)
      if name == :primary
        primary = @primary_adapter.call
        raise HakumiORM::Error, "No primary adapter configured" unless primary

        return primary
      end

      existing = @named_adapters[name]
      return existing if existing

      built = @connect_adapter.call(named_database(name))
      @named_adapters[name] = built
      built
    end

    sig { void }
    def close_named_adapters!
      @named_adapters.each_value(&:close)
      @named_adapters.clear
    end
  end
end
