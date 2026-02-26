# typed: strict
# frozen_string_literal: true

require "fileutils"

module HakumiORM
  module Codegen
    # Filesystem writes for code generation, including write-if-missing behavior.
    class FileWriter
      extend T::Sig

      sig { params(path: String).void }
      def mkdir_p(path)
        FileUtils.mkdir_p(path)
      end

      sig { params(path: String, content: String).void }
      def write(path, content)
        File.write(path, content)
      end

      sig { params(path: String, content: String).void }
      def write_if_missing(path, content)
        return if File.exist?(path)

        File.write(path, content)
      end

      sig { params(path: String).returns(T::Boolean) }
      def exist?(path)
        File.exist?(path)
      end
    end
  end
end
