# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Discovers migration files and loads migration classes from filenames.
    class Loader
      extend T::Sig

      MIGRATION_FILE_PATTERN = T.let(/\A(\d{14})_(\w+)\.rb\z/, Regexp)

      sig { params(migrations_path: String).void }
      def initialize(migrations_path)
        @migrations_path = T.let(migrations_path, String)
      end

      sig { returns(T::Array[FileInfo]) }
      def migration_files
        return [] unless Dir.exist?(@migrations_path)

        Dir.children(@migrations_path).grep(MIGRATION_FILE_PATTERN).sort.filter_map do |filename|
          match = filename.match(MIGRATION_FILE_PATTERN)
          next unless match

          version = match[1]
          next unless version

          name = filename.delete_suffix(".rb").sub(/\A\d{14}_/, "") # security-audit: allow-sub
          FileInfo.new(version: version, name: name, filename: filename)
        end
      end

      sig { params(file_info: FileInfo).returns(T.class_of(Migration)) }
      def load_migration(file_info)
        path = File.join(@migrations_path, file_info.filename)
        class_name = file_info.name.split("_").map(&:capitalize).join

        begin
          load path
        rescue SyntaxError, LoadError => e
          raise HakumiORM::Error, "Failed to load migration #{file_info.filename}: #{e.message}"
        end

        klass = Migration.lookup(class_name)
        unless klass
          raise HakumiORM::Error,
                "Migration #{file_info.filename} must define class #{class_name} " \
                "that must inherit from HakumiORM::Migration (expected from filename)"
        end

        klass
      end
    end
  end
end
