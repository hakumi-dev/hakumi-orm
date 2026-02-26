# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Stores applied migration versions in `hakumi_migrations`.
    class VersionStore
      extend T::Sig

      CREATE_TABLE_SQL = T.let(<<~SQL, String)
        CREATE TABLE IF NOT EXISTS hakumi_migrations (
          version varchar(14) PRIMARY KEY,
          name varchar(255) NOT NULL,
          migrated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { void }
      def ensure_table!
        @adapter.exec(CREATE_TABLE_SQL).close
      end

      sig { returns(T::Array[String]) }
      def applied_versions
        result = @adapter.exec("SELECT version FROM hakumi_migrations ORDER BY version")
        versions = T.let([], T::Array[String])
        i = T.let(0, Integer)
        while i < result.row_count
          versions << result.fetch_value(i, 0)
          i += 1
        end
        result.close
        versions
      end

      sig { returns(T.nilable(String)) }
      def current_version
        applied_versions.max
      end

      sig { params(version: String, name: String).void }
      def record_version(version, name)
        d = @adapter.dialect
        sql = "INSERT INTO hakumi_migrations (version, name) VALUES (#{d.bind_marker(0)}, #{d.bind_marker(1)})"
        result = @adapter.exec_params(sql, [version, name])
        result.close
      end

      sig { params(version: String).void }
      def remove_version(version)
        d = @adapter.dialect
        sql = "DELETE FROM hakumi_migrations WHERE version = #{d.bind_marker(0)}"
        result = @adapter.exec_params(sql, [version])
        result.close
      end
    end
  end
end
