# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require_relative "hakumi_orm/version"

module HakumiORM
  class Error < StandardError; end
end

require_relative "hakumi_orm/json"

require_relative "hakumi_orm/bind"

require_relative "hakumi_orm/field_ref"
require_relative "hakumi_orm/order_clause"
require_relative "hakumi_orm/join_clause"

require_relative "hakumi_orm/compiled_query"

require_relative "hakumi_orm/expr"

require_relative "hakumi_orm/field"
require_relative "hakumi_orm/field/comparable_field"
require_relative "hakumi_orm/field/text_field"
require_relative "hakumi_orm/field/int_field"
require_relative "hakumi_orm/field/float_field"
require_relative "hakumi_orm/field/decimal_field"
require_relative "hakumi_orm/field/time_field"
require_relative "hakumi_orm/field/date_field"
require_relative "hakumi_orm/field/str_field"
require_relative "hakumi_orm/field/bool_field"
require_relative "hakumi_orm/field/json_field"
require_relative "hakumi_orm/field/enum_field"
require_relative "hakumi_orm/field/int_array_field"
require_relative "hakumi_orm/field/str_array_field"
require_relative "hakumi_orm/field/float_array_field"
require_relative "hakumi_orm/field/bool_array_field"

require_relative "hakumi_orm/assignment"
require_relative "hakumi_orm/cast"

require_relative "hakumi_orm/dialect"
require_relative "hakumi_orm/dialect/postgresql"
require_relative "hakumi_orm/dialect/mysql"
require_relative "hakumi_orm/dialect/sqlite"

require_relative "hakumi_orm/adapter"
require_relative "hakumi_orm/adapter/postgresql_result"
require_relative "hakumi_orm/adapter/postgresql"

require_relative "hakumi_orm/sql_compiler"
require_relative "hakumi_orm/preload_node"

require_relative "hakumi_orm/errors"
require_relative "hakumi_orm/stale_object_error"
require_relative "hakumi_orm/schema_drift_error"
require_relative "hakumi_orm/validation_error"
require_relative "hakumi_orm/adapter/timeout_error"
require_relative "hakumi_orm/adapter/connection_pool"

require_relative "hakumi_orm/configuration"

module HakumiORM
  class << self
    extend T::Sig

    sig { returns(Configuration) }
    def config
      @config ||= T.let(Configuration.new, T.nilable(Configuration))
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
end

require_relative "hakumi_orm/relation"
