# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require_relative "hakumi_orm/version"

# Internal component for .
module HakumiORM
  class Error < StandardError; end
end

require_relative "hakumi_orm/loggable"
require_relative "hakumi_orm/json"
require_relative "hakumi_orm/byte_time"
require_relative "hakumi_orm/field_ref"
require_relative "hakumi_orm/order_clause"
require_relative "hakumi_orm/join_clause"
require_relative "hakumi_orm/assignment"
require_relative "hakumi_orm/bind"
require_relative "hakumi_orm/cast"

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
require_relative "hakumi_orm/field/int_enum_field"
require_relative "hakumi_orm/field/int_array_field"
require_relative "hakumi_orm/field/str_array_field"
require_relative "hakumi_orm/field/float_array_field"
require_relative "hakumi_orm/field/bool_array_field"

require_relative "hakumi_orm/expr"
require_relative "hakumi_orm/compiled_query"

require_relative "hakumi_orm/dialect"
require_relative "hakumi_orm/dialect/postgresql"
require_relative "hakumi_orm/dialect/mysql"
require_relative "hakumi_orm/dialect/sqlite"

require_relative "hakumi_orm/sql_compiler"
require_relative "hakumi_orm/sql_log_formatter"

require_relative "hakumi_orm/ports"
require_relative "hakumi_orm/ports/adapter_factory_port"
require_relative "hakumi_orm/ports/schema_introspection_port"
require_relative "hakumi_orm/ports/migration_runner_factory_port"
require_relative "hakumi_orm/ports/task_output_port"
require_relative "hakumi_orm/ports/fixtures_loader_port"
require_relative "hakumi_orm/adapter"
require_relative "hakumi_orm/adapter/timeout_error"
require_relative "hakumi_orm/adapter/connection_pool"

require_relative "hakumi_orm/preload_node"
require_relative "hakumi_orm/relation_preloader"
require_relative "hakumi_orm/record_runtime"

require_relative "hakumi_orm/errors"
require_relative "hakumi_orm/validation/validatable_interface"
require_relative "hakumi_orm/validation/validatable"
require_relative "hakumi_orm/validation/rule_payload"
require_relative "hakumi_orm/validation/rule_context"
require_relative "hakumi_orm/validation/contract_dsl"
require_relative "hakumi_orm/validation/contract_dsl_parsing"
require_relative "hakumi_orm/validation/validators/base"
require_relative "hakumi_orm/validation/validators/presence"
require_relative "hakumi_orm/validation/validators/blank"
require_relative "hakumi_orm/validation/validators/length"
require_relative "hakumi_orm/validation/validators/format"
require_relative "hakumi_orm/validation/validators/numericality"
require_relative "hakumi_orm/validation/validators/inclusion"
require_relative "hakumi_orm/validation/validators/exclusion"
require_relative "hakumi_orm/validation/validators/comparison"
require_relative "hakumi_orm/validation/validators/registry"
require_relative "hakumi_orm/form_model_adapter"
require_relative "hakumi_orm/form_model/name"
require_relative "hakumi_orm/form_model/noop_adapter"
require_relative "hakumi_orm/form_model"
require_relative "hakumi_orm/stale_object_error"
require_relative "hakumi_orm/validation_error"
require_relative "hakumi_orm/schema_drift/error"
require_relative "hakumi_orm/schema_drift/issues"
require_relative "hakumi_orm/schema_drift/reporter"
require_relative "hakumi_orm/pending_migration_error"

require_relative "hakumi_orm/inflector"
require_relative "hakumi_orm/adapter_registry"
require_relative "hakumi_orm/database_config"
require_relative "hakumi_orm/database_url_parser"
require_relative "hakumi_orm/database_config_builder"
require_relative "hakumi_orm/configuration"
require_relative "hakumi_orm/configuration_schema_guards"
require_relative "hakumi_orm/configuration_adapter_factory"
require_relative "hakumi_orm/application"
require_relative "hakumi_orm/application/schema_introspection"
require_relative "hakumi_orm/internal"
require_relative "hakumi_orm/application/fixtures_load"
require_relative "hakumi_orm/scaffold_generator"
require_relative "hakumi_orm/schema_drift/checker"
require_relative "hakumi_orm/setup_generator"

require_relative "hakumi_orm/framework"
begin
  require_relative "hakumi_orm/framework/rails"
rescue LoadError => e
  raise unless e.respond_to?(:path) && e.path == "rails/railtie"
end

# Internal module for HakumiORM.
module HakumiORM
  class << self
    extend T::Sig

    sig { returns(Configuration) }
    def config
      @config ||= T.let(Configuration.new, T.nilable(Configuration))
    end

    sig { params(blk: T.proc.params(config: Configuration).void).void }
    def configure(&blk)
      open_type_registry!
      blk.call(config)
    ensure
      close_type_registry!
    end

    sig { returns(T::Boolean) }
    def type_registry_open?
      current = T.let(@type_registry_open, T.nilable(T::Boolean))
      current != false
    end

    sig { void }
    def open_type_registry!
      @type_registry_open = T.let(nil, T.nilable(T::Boolean))
    end

    sig { void }
    def close_type_registry!
      @type_registry_open = T.let(false, T.nilable(T::Boolean))
    end

    sig { params(word: String).returns(String) }
    def singularize(word)
      config.singularizer.call(word)
    end

    sig { returns(Ports::AdapterFactoryPort) }
    def adapter_factory_port
      @adapter_factory_port ||= T.let(Adapter::FactoryGateway.new, T.nilable(Ports::AdapterFactoryPort))
    end

    sig { params(adapter_factory_port: Ports::AdapterFactoryPort).void }
    attr_writer :adapter_factory_port

    sig { returns(Ports::SchemaIntrospectionPort) }
    def schema_introspection_port
      @schema_introspection_port ||= T.let(
        Adapter::SchemaIntrospectionGateway.new,
        T.nilable(Ports::SchemaIntrospectionPort)
      )
    end

    sig { params(schema_introspection_port: Ports::SchemaIntrospectionPort).void }
    attr_writer :schema_introspection_port

    sig { returns(Ports::MigrationRunnerFactoryPort) }
    def migration_runner_factory_port
      @migration_runner_factory_port ||= T.let(
        Adapter::MigrationRunnerFactoryGateway.new,
        T.nilable(Ports::MigrationRunnerFactoryPort)
      )
    end

    sig { params(migration_runner_factory_port: Ports::MigrationRunnerFactoryPort).void }
    attr_writer :migration_runner_factory_port

    sig { returns(Ports::TaskOutputPort) }
    def task_output_port
      @task_output_port ||= T.let(Adapter::TaskOutputGateway.new, T.nilable(Ports::TaskOutputPort))
    end

    sig { params(task_output_port: Ports::TaskOutputPort).void }
    attr_writer :task_output_port

    sig { returns(Ports::FixturesLoaderPort) }
    def fixtures_loader_port
      @fixtures_loader_port ||= T.let(Adapter::FixturesLoaderGateway.new, T.nilable(Ports::FixturesLoaderPort))
    end

    sig { params(fixtures_loader_port: Ports::FixturesLoaderPort).void }
    attr_writer :fixtures_loader_port

    sig { params(name: T.nilable(Symbol)).returns(Adapter::Base) }
    def adapter(name = nil)
      return config.adapter_for(name) if name

      override = T.cast(Thread.current[:hakumi_adapter_name], T.nilable(Symbol))
      return (override == :primary ? primary_adapter : config.adapter_for(override)) if override

      primary_adapter
    end

    sig { params(adapter: Adapter::Base).void }
    def adapter=(adapter)
      config.adapter = adapter
    end

    sig do
      type_parameters(:R)
        .params(name: Symbol, blk: T.proc.returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def using(name, &blk)
      config.adapter_for(name) unless name == :primary
      previous = T.cast(Thread.current[:hakumi_adapter_name], T.nilable(Symbol))
      Thread.current[:hakumi_adapter_name] = name
      blk.call
    ensure
      Thread.current[:hakumi_adapter_name] = previous
    end

    sig { void }
    def reset_config!
      config.close_named_adapters!
      @config = T.let(nil, T.nilable(Configuration))
      @adapter_factory_port = T.let(nil, T.nilable(Ports::AdapterFactoryPort))
      @schema_introspection_port = T.let(nil, T.nilable(Ports::SchemaIntrospectionPort))
      @migration_runner_factory_port = T.let(nil, T.nilable(Ports::MigrationRunnerFactoryPort))
      @task_output_port = T.let(nil, T.nilable(Ports::TaskOutputPort))
      @fixtures_loader_port = T.let(nil, T.nilable(Ports::FixturesLoaderPort))
      Thread.current[:hakumi_adapter_name] = nil
      open_type_registry!
    end

    sig { params(table_name: String, blk: T.proc.params(builder: Codegen::AssociationBuilder).void).void }
    def associate(table_name, &blk)
      builder = Codegen::AssociationBuilder.new(table_name)
      blk.call(builder)
      assoc_registry = (@_association_registry ||= T.let({}, T.nilable(T::Hash[String, T::Array[Codegen::CustomAssociation]])))
      (assoc_registry[table_name] ||= []).concat(builder.associations)
    end

    sig { void }
    def clear_associations!
      @_association_registry = T.let({}, T.nilable(T::Hash[String, T::Array[Codegen::CustomAssociation]]))
    end

    sig { returns(T::Hash[String, T::Array[Codegen::CustomAssociation]]) }
    def drain_associations!
      result = @_association_registry || {}
      @_association_registry = T.let(nil, T.nilable(T::Hash[String, T::Array[Codegen::CustomAssociation]]))
      result
    end

    sig { params(table_name: String, blk: T.proc.params(builder: Codegen::EnumBuilder).void).void }
    def define_enums(table_name, &blk)
      builder = Codegen::EnumBuilder.new(table_name)
      blk.call(builder)
      enum_registry = (@_enum_registry ||= T.let({}, T.nilable(T::Hash[String, T::Array[Codegen::EnumDefinition]])))
      (enum_registry[table_name] ||= []).concat(builder.definitions)
    end

    sig { void }
    def clear_enums!
      @_enum_registry = T.let({}, T.nilable(T::Hash[String, T::Array[Codegen::EnumDefinition]]))
    end

    sig { returns(T::Hash[String, T::Array[Codegen::EnumDefinition]]) }
    def drain_enums!
      result = @_enum_registry || {}
      @_enum_registry = T.let(nil, T.nilable(T::Hash[String, T::Array[Codegen::EnumDefinition]]))
      result
    end

    sig { params(table_name: String, skip: T::Boolean, annotation_lines: T::Array[String]).void }
    def on_table(table_name, skip: false, annotation_lines: [])
      hook = Codegen::TableHook.new(skip: skip, annotation_lines: annotation_lines)
      hook_registry = (@_table_hook_registry ||= T.let({}, T.nilable(T::Hash[String, Codegen::TableHook])))
      hook_registry[table_name] = hook
    end

    sig { void }
    def clear_table_hooks!
      @_table_hook_registry = T.let({}, T.nilable(T::Hash[String, Codegen::TableHook]))
    end

    sig { returns(T::Hash[String, Codegen::TableHook]) }
    def drain_table_hooks!
      result = @_table_hook_registry || {}
      @_table_hook_registry = T.let(nil, T.nilable(T::Hash[String, Codegen::TableHook]))
      result
    end

    private

    sig { returns(Adapter::Base) }
    def primary_adapter
      adapter = config.adapter
      raise Error, "No adapter configured. Use HakumiORM.configure { |c| c.adapter = ... }" unless adapter

      adapter
    end
  end
end

require_relative "hakumi_orm/relation"
