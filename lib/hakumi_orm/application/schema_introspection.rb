# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Application
    # Reads live schema metadata from an adapter through dialect-specific readers.
    class SchemaIntrospection
      extend T::Sig

      sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
      def self.read_tables(config, adapter)
        raw = HakumiORM.schema_introspection_port.read_tables(config: config, adapter: adapter)
        T.cast(raw, T::Hash[String, Codegen::TableInfo])
      end
    end
  end
end
