# typed: strict
# frozen_string_literal: true

# Internal component for codegen/generator_options.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class GeneratorOptions
      extend T::Sig

      sig { returns(T.nilable(Dialect::Base)) }
      attr_reader :dialect

      sig { returns(T.nilable(String)) }
      attr_reader :output_dir

      sig { returns(T.nilable(String)) }
      attr_reader :module_name

      sig { returns(T.nilable(String)) }
      attr_reader :models_dir

      sig { returns(T.nilable(String)) }
      attr_reader :contracts_dir

      sig { returns(T::Hash[String, String]) }
      attr_reader :soft_delete_tables

      sig { returns(T.nilable(String)) }
      attr_reader :created_at_column

      sig { returns(T.nilable(String)) }
      attr_reader :updated_at_column

      sig { returns(T::Hash[String, T::Array[CustomAssociation]]) }
      attr_reader :custom_associations

      sig { returns(T::Hash[String, T::Array[EnumDefinition]]) }
      attr_reader :user_enums

      sig { returns(T::Array[String]) }
      attr_reader :internal_tables

      sig { returns(T.nilable(String)) }
      attr_reader :schema_fingerprint

      sig { returns(T::Hash[String, TableHook]) }
      attr_reader :table_hooks

      sig do
        params(
          dialect: T.nilable(Dialect::Base),
          output_dir: T.nilable(String),
          module_name: T.nilable(String),
          models_dir: T.nilable(String),
          contracts_dir: T.nilable(String),
          soft_delete_tables: T::Hash[String, String],
          created_at_column: T.nilable(String),
          updated_at_column: T.nilable(String),
          custom_associations: T::Hash[String, T::Array[CustomAssociation]],
          user_enums: T::Hash[String, T::Array[EnumDefinition]],
          internal_tables: T::Array[String],
          schema_fingerprint: T.nilable(String),
          table_hooks: T::Hash[String, TableHook]
        ).void
      end
      def initialize(
        dialect: nil,
        output_dir: nil,
        module_name: nil,
        models_dir: nil,
        contracts_dir: nil,
        soft_delete_tables: {},
        created_at_column: "created_at",
        updated_at_column: "updated_at",
        custom_associations: {},
        user_enums: {},
        internal_tables: [],
        schema_fingerprint: nil,
        table_hooks: {}
      )
        @dialect = T.let(dialect, T.nilable(Dialect::Base))
        @output_dir = T.let(output_dir, T.nilable(String))
        @module_name = T.let(module_name, T.nilable(String))
        @models_dir = T.let(models_dir, T.nilable(String))
        @contracts_dir = T.let(contracts_dir, T.nilable(String))
        @soft_delete_tables = T.let(soft_delete_tables.dup.freeze, T::Hash[String, String])
        @created_at_column = T.let(created_at_column, T.nilable(String))
        @updated_at_column = T.let(updated_at_column, T.nilable(String))
        @custom_associations = T.let(
          custom_associations.transform_values { |v| v.dup.freeze }.dup.freeze,
          T::Hash[String, T::Array[CustomAssociation]]
        )
        @user_enums = T.let(
          user_enums.transform_values { |v| v.dup.freeze }.dup.freeze,
          T::Hash[String, T::Array[EnumDefinition]]
        )
        @internal_tables = T.let(internal_tables.dup.freeze, T::Array[String])
        @schema_fingerprint = T.let(schema_fingerprint, T.nilable(String))
        @table_hooks = T.let(table_hooks.dup.freeze, T::Hash[String, TableHook])
      end
    end
  end
end
