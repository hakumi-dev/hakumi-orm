# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class EnumLoader
      extend T::Sig

      sig { params(path: String).returns(T::Hash[String, T::Array[EnumDefinition]]) }
      def self.load(path)
        HakumiORM.clear_enums!
        return {} unless File.directory?(path)

        Dir.glob(File.join(path, "*.rb")).each do |file|
          Kernel.load(file)
        end

        HakumiORM.drain_enums!
      end
    end
  end
end
