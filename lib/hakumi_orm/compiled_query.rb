# typed: strict
# frozen_string_literal: true

module HakumiORM
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
    end

    sig { returns(T::Array[PGValue]) }
    def pg_params
      @binds.map(&:pg_value)
    end
  end
end
