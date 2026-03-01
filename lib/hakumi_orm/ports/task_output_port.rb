# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Ports
    # Port for task/CLI output side effects.
    module TaskOutputPort
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(result: T::Hash[Symbol, T::Array[String]]).void }
      def install_result(result); end

      sig { abstract.params(count: Integer, output_dir: String).void }
      def generated_tables(count:, output_dir:); end

      sig { abstract.params(name: String, output_dir: String).void }
      def custom_type_scaffolded(name:, output_dir:); end

      sig { abstract.params(applied: T::Array[Migration::FileInfo], version: String).void }
      def migrate_result(applied:, version:); end

      sig { abstract.params(count: Integer, version: String).void }
      def rollback_result(count:, version:); end

      sig { abstract.params(statuses: T::Array[T::Hash[Symbol, String]]).void }
      def migration_status(statuses); end

      sig { abstract.params(version: String).void }
      def current_version(version); end

      sig { abstract.params(filepath: String).void }
      def migration_file_created(filepath); end

      sig do
        abstract
          .params(table_name: String, created: T::Array[String], models_dir: T.nilable(String), contracts_dir: T.nilable(String))
          .void
      end
      def scaffold_result(table_name:, created:, models_dir:, contracts_dir:); end

      sig { abstract.params(task_prefix: String).void }
      def fingerprint_skip_generate(task_prefix:); end

      sig { abstract.void }
      def schema_check_ok; end

      sig { abstract.params(messages: T::Array[String]).void }
      def schema_check_errors(messages); end

      sig { abstract.params(path: String).void }
      def seed_missing(path); end

      sig { abstract.params(path: String).void }
      def seed_loaded(path); end

      sig { abstract.params(path: String, table_count: Integer).void }
      def fixtures_loaded(path:, table_count:); end

      sig do
        abstract
          .params(path: String, table_count: Integer, row_count: Integer, table_rows: T::Hash[String, Integer])
          .void
      end
      def fixtures_dry_run(path:, table_count:, row_count:, table_rows:); end

      sig { abstract.params(table_name: String, lines: T::Array[String]).void }
      def associations_for_table(table_name, lines); end
    end
  end
end
