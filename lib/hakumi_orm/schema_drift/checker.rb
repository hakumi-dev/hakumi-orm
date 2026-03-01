# typed: strict
# frozen_string_literal: true

require "digest"
require_relative "issues"
require_relative "reporter"

module HakumiORM
  # Checks database schema state and produces drift findings for tooling/CLI.
  class SchemaDriftChecker
    extend T::Sig

    sig { params(config: Configuration, adapter: Adapter::Base).returns(T::Hash[String, Codegen::TableInfo]) }
    def self.read_schema(config, adapter)
      Application::SchemaIntrospection.read_tables(config, adapter)
    end

    sig { params(config: Configuration, adapter: Adapter::Base, internal_tables: T::Array[String]).void }
    def initialize(config:, adapter:, internal_tables: [])
      @config = T.let(config, Configuration)
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
      SchemaDrift::Reporter.render_all(check_issues)
    end

    sig { returns(T::Array[SchemaDrift::Issue]) }
    def check_issues
      issues = T.let([], T::Array[SchemaDrift::Issue])
      pending = pending_migrations_issue
      issues << pending if pending
      schema = schema_drift_issue
      issues << schema if schema
      issues
    end

    private

    sig { returns(T.nilable(SchemaDrift::PendingMigrationsIssue)) }
    def pending_migrations_issue
      pending = Migration::SchemaFingerprint.pending_migrations(@adapter, @config.migrations_path)
      return nil if pending.empty?

      SchemaDrift::PendingMigrationsIssue.new(versions: pending)
    end

    sig { returns(T.nilable(SchemaDrift::Issue)) }
    def schema_drift_issue
      stored_fp = Migration::SchemaFingerprint.read_from_db(@adapter)
      return SchemaDrift::NoSchemaFingerprintIssue.new unless stored_fp

      canonical, live_fp = compute_live
      return nil if live_fp == stored_fp

      stored_canonical = Migration::SchemaFingerprint.read_canonical_from_db(@adapter)
      diff = stored_canonical ? Migration::SchemaFingerprint.diff_canonical(stored_canonical, canonical) : []
      SchemaDrift::SchemaMismatchIssue.new(
        expected_fingerprint: stored_fp,
        actual_fingerprint: live_fp,
        diff_lines: diff
      )
    end

    sig { returns([String, String]) }
    def compute_live
      tables = read_schema(@config)
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
