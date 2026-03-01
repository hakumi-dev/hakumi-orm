# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Ports
    # Port for reading live DB schema as codegen TableInfo objects.
    module SchemaIntrospectionPort
      extend T::Sig
      extend T::Helpers

      interface!

      sig do
        abstract
          .params(config: Configuration, adapter: Adapter::Base)
          .returns(T::Hash[String, Codegen::TableInfo])
      end
      def read_tables(config:, adapter:); end
    end
  end
end
