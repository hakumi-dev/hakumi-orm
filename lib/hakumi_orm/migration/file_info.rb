# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Typed metadata for a migration file discovered on disk.
    class FileInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :version

      sig { returns(String) }
      attr_reader :name

      sig { returns(String) }
      attr_reader :filename

      sig { params(version: String, name: String, filename: String).void }
      def initialize(version:, name:, filename:)
        @version = T.let(version, String)
        @name = T.let(name, String)
        @filename = T.let(filename, String)
      end
    end
  end
end
