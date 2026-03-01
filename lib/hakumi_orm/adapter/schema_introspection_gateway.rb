# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
    # Infrastructure implementation of SchemaIntrospectionPort.
    class SchemaIntrospectionGateway
      include Ports::SchemaIntrospectionPort

      extend T::Sig

      sig { override.params(config: T.anything, adapter: T.anything).returns(T::Hash[String, T.anything]) }
      def read_tables(config:, adapter:)
        require "hakumi_orm/codegen"

        typed_config = T.cast(config, Configuration)
        typed_adapter = T.cast(adapter, Adapter::Base)

        case typed_config.adapter_name
        when :postgresql
          Codegen::SchemaReader.new(typed_adapter).read_tables(schema: "public")
        when :mysql
          schema = typed_config.database
          raise HakumiORM::Error, "config.database is required for MySQL codegen" unless schema

          Codegen::MysqlSchemaReader.new(typed_adapter).read_tables(schema: schema)
        when :sqlite
          Codegen::SqliteSchemaReader.new(typed_adapter).read_tables
        else
          raise HakumiORM::Error, "Unknown adapter_name: #{typed_config.adapter_name}"
        end
      end
    end
  end
end
