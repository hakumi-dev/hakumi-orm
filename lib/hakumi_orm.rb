# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require_relative "hakumi_orm/version"
require_relative "hakumi_orm/json"
require_relative "hakumi_orm/bind"
require_relative "hakumi_orm/field_ref"
require_relative "hakumi_orm/expr"
require_relative "hakumi_orm/field"
require_relative "hakumi_orm/cast"
require_relative "hakumi_orm/compiled_query"
require_relative "hakumi_orm/dialect"
require_relative "hakumi_orm/dialect/postgresql"
require_relative "hakumi_orm/adapter"
require_relative "hakumi_orm/adapter/postgresql"
require_relative "hakumi_orm/sql_compiler"
require_relative "hakumi_orm/preload_node"
require_relative "hakumi_orm/relation"
require_relative "hakumi_orm/configuration"

module HakumiORM
  class << self
    extend T::Sig

    sig { returns(Configuration) }
    def config
      @config = T.let(@config, T.nilable(Configuration))
      @config ||= Configuration.new
    end

    sig { params(blk: T.proc.params(config: Configuration).void).void }
    def configure(&blk)
      blk.call(config)
    end

    sig { returns(Adapter::Base) }
    def adapter
      adapter = config.adapter
      raise Error, "No adapter configured. Use HakumiORM.configure { |c| c.adapter = ... }" unless adapter

      adapter
    end

    sig { params(adapter: Adapter::Base).void }
    def adapter=(adapter)
      config.adapter = adapter
    end

    sig { void }
    def reset_config!
      @config = T.let(nil, T.nilable(Configuration))
    end
  end

  class Error < StandardError; end
end

require_relative "hakumi_orm/adapter/connection_pool"
require_relative "hakumi_orm/errors"
