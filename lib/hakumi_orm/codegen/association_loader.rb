# typed: strict
# frozen_string_literal: true

# Internal component for codegen/association_loader.
module HakumiORM
  module Codegen
    # Internal class for HakumiORM.
    class AssociationLoader
      extend T::Sig

      sig { params(path: String).returns(T::Hash[String, T::Array[CustomAssociation]]) }
      def self.load(path)
        HakumiORM.clear_associations!
        return {} unless File.directory?(path)

        Dir.glob(File.join(path, "*.rb")).each do |file|
          Kernel.load(file)
        end

        HakumiORM.drain_associations!
      end
    end
  end
end
