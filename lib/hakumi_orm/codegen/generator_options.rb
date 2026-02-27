# typed: strict
# frozen_string_literal: true

# Internal component for codegen/generator_options.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class GeneratorOptions < T::Struct
      const :dialect, T.nilable(Dialect::Base), default: nil
      const :output_dir, T.nilable(String), default: nil
      const :module_name, T.nilable(String), default: nil
      const :models_dir, T.nilable(String), default: nil
      const :contracts_dir, T.nilable(String), default: nil
      const :soft_delete_tables, T::Hash[String, String], default: {}
      const :created_at_column, T.nilable(String), default: "created_at"
      const :updated_at_column, T.nilable(String), default: "updated_at"
      const :custom_associations, T::Hash[String, T::Array[CustomAssociation]], default: {}
      const :user_enums, T::Hash[String, T::Array[EnumDefinition]], default: {}
      const :internal_tables, T::Array[String], default: []
      const :schema_fingerprint, T.nilable(String), default: nil
    end
  end
end
