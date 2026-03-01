# typed: strict
# frozen_string_literal: true

# Internal component for compiled_query.
module HakumiORM
  # Internal class for HakumiORM.
  class CompiledQuery
    extend T::Sig

    sig { returns(String) }
    attr_reader :sql

    sig { returns(T::Array[Bind]) }
    attr_reader :binds

    sig { params(sql: String, binds: T::Array[Bind]).void }
    def initialize(sql, binds)
      @sql = T.let(sql, String)
      @binds = T.let(binds, T::Array[Bind])
      @params_cache = T.let({}, T::Hash[Symbol, T::Array[DBValue]])
    end

    sig { returns(T::Array[DBValue]) }
    def db_params
      @binds.map(&:serialize)
    end

    sig { params(dialect: Dialect::Base).returns(T::Array[DBValue]) }
    def params_for(dialect)
      key = dialect.name
      cached = @params_cache[key]
      return cached if cached

      params = dialect.encode_binds(@binds)
      @params_cache[key] = params
      params
    end
  end
end
