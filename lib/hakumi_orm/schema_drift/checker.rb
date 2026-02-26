# typed: strict
# frozen_string_literal: true

require "digest"

module HakumiORM
  class SchemaDriftChecker
    extend T::Sig

    sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
    def self.read_schema(config, adapter)
      case config.adapter_name
      when :postgresql
        Codegen::SchemaReader.new(adapter).read_tables(schema: "public")
      when :mysql
        schema = config.database
        raise HakumiORM::Error, "config.database is required for MySQL codegen" unless schema

        Codegen::MysqlSchemaReader.new(adapter).read_tables(schema: schema)
      when :sqlite
        Codegen::SqliteSchemaReader.new(adapter).read_tables
      else
        raise HakumiORM::Error, "Unknown adapter_name: #{config.adapter_name}"
      end
    end

    sig { params(adapter: Adapter::Base, internal_tables: T::Array[String]).void }
    def initialize(adapter, internal_tables: [])
      @adapter = T.let(adapter, Adapter::Base)
      @internal_tables = T.let(internal_tables, T::Array[String])
    end

    sig { void }
    def update_fingerprint!
      canonical, fingerprint = compute_live
      Migration::SchemaFingerprint.store!(@adapter, fingerprint, canonical)
    end

    sig { returns(T::Array[String]) }
    def check
      lines = T.let([], T::Array[String])
      lines.concat(check_pending_migrations)
      lines.concat(check_schema_drift)
      lines
    end

    private

    sig { returns(T::Array[String]) }
    def check_pending_migrations
      config = HakumiORM.config
      pending = Migration::SchemaFingerprint.pending_migrations(@adapter, config.migrations_path)
      return [] if pending.empty?

      lines = T.let(["#{pending.size} pending migration(s):"], T::Array[String])
      pending.each { |v| lines << "  - #{v}" }
      lines << ""
      lines << "  Run 'rake db:migrate' to apply."
      lines
    end

    sig { returns(T::Array[String]) }
    def check_schema_drift
      stored_fp = Migration::SchemaFingerprint.read_from_db(@adapter)
      return ["No schema fingerprint stored. Run 'rake db:generate' first."] unless stored_fp

      canonical, live_fp = compute_live
      return [] if live_fp == stored_fp

      lines = T.let(["Schema drift detected!"], T::Array[String])
      lines << ""
      lines << "  Expected: #{stored_fp[0..15]}..."
      lines << "  Actual:   #{live_fp[0..15]}..."

      stored_canonical = Migration::SchemaFingerprint.read_canonical_from_db(@adapter)
      if stored_canonical
        diff = Migration::SchemaFingerprint.diff_canonical(stored_canonical, canonical)
        unless diff.empty?
          lines << ""
          diff.each { |l| lines << "  #{l}" }
        end
      end

      lines << ""
      lines << "  Run 'rake db:generate' to update generated code."
      lines
    end

    sig { returns([String, String]) }
    def compute_live
      config = HakumiORM.config
      tables = read_schema(config)
      skip = @internal_tables.to_set
      user_tables = T.let({}, T::Hash[String, Codegen::TableInfo])
      tables.each { |name, info| user_tables[name] = info unless skip.include?(name) }
      canonical = Migration::SchemaFingerprint.build_canonical(user_tables)
      fingerprint = Digest::SHA256.hexdigest(canonical)
      [canonical, fingerprint]
    end

    sig { params(config: Configuration).returns(T::Hash[String, Codegen::TableInfo]) }
    def read_schema(config)
      self.class.read_schema(config, @adapter)
    end
  end
end
