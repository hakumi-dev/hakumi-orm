# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Typed metadata for a migration file discovered on disk.
    class FileInfo < T::Struct
      const :version, String
      const :name, String
      const :filename, String
    end
  end
end
