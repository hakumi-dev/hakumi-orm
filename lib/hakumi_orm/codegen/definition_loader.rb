# typed: strict
# frozen_string_literal: true

# Internal component for codegen/definition_loader.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class DefinitionLoader
      extend T::Sig

      Definitions = T.type_alias do
        {
          associations: T::Hash[String, T::Array[CustomAssociation]],
          enums: T::Hash[String, T::Array[EnumDefinition]],
          table_hooks: T::Hash[String, TableHook]
        }
      end

      sig { params(path: String).returns(Definitions) }
      def self.load(path)
        HakumiORM.clear_associations!
        HakumiORM.clear_enums!
        HakumiORM.clear_table_hooks!

        if File.file?(path)
          Kernel.load(path)
        elsif File.directory?(path)
          Dir.glob(File.join(path, "*.rb")).each { |f| Kernel.load(f) }
        end

        {
          associations: HakumiORM.drain_associations!,
          enums: HakumiORM.drain_enums!,
          table_hooks: HakumiORM.drain_table_hooks!
        }
      end
    end
  end
end
