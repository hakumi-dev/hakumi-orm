# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
    # Infrastructure implementation of TaskOutputPort.
    class TaskOutputGateway
      include Ports::TaskOutputPort

      extend T::Sig

      sig { override.params(result: T::Hash[Symbol, T::Array[String]]).void }
      def install_result(result)
        HakumiORM::TaskOutput.install_result(result)
      end

      sig { override.params(count: Integer, output_dir: String).void }
      def generated_tables(count:, output_dir:)
        HakumiORM::TaskOutput.generated_tables(count: count, output_dir: output_dir)
      end

      sig { override.params(name: String, output_dir: String).void }
      def custom_type_scaffolded(name:, output_dir:)
        HakumiORM::TaskOutput.custom_type_scaffolded(name: name, output_dir: output_dir)
      end

      sig { override.params(applied: T::Array[Migration::FileInfo], version: String).void }
      def migrate_result(applied:, version:)
        HakumiORM::TaskOutput.migrate_result(applied: applied, version: version)
      end

      sig { override.params(count: Integer, version: String).void }
      def rollback_result(count:, version:)
        HakumiORM::TaskOutput.rollback_result(count: count, version: version)
      end

      sig { override.params(statuses: T::Array[T::Hash[Symbol, String]]).void }
      def migration_status(statuses)
        HakumiORM::TaskOutput.migration_status(statuses)
      end

      sig { override.params(version: String).void }
      def current_version(version)
        HakumiORM::TaskOutput.current_version(version)
      end

      sig { override.params(filepath: String).void }
      def migration_file_created(filepath)
        HakumiORM::TaskOutput.migration_file_created(filepath)
      end

      sig do
        override
          .params(table_name: String, created: T::Array[String], models_dir: T.nilable(String), contracts_dir: T.nilable(String))
          .void
      end
      def scaffold_result(table_name:, created:, models_dir:, contracts_dir:)
        HakumiORM::TaskOutput.scaffold_result(
          table_name: table_name,
          created: created,
          models_dir: models_dir,
          contracts_dir: contracts_dir
        )
      end

      sig { override.params(task_prefix: String).void }
      def fingerprint_skip_generate(task_prefix:)
        HakumiORM::TaskOutput.fingerprint_skip_generate(task_prefix: task_prefix)
      end

      sig { override.void }
      def schema_check_ok
        HakumiORM::TaskOutput.schema_check_ok
      end

      sig { override.params(messages: T::Array[String]).void }
      def schema_check_errors(messages)
        HakumiORM::TaskOutput.schema_check_errors(messages)
      end

      sig { override.params(path: String).void }
      def seed_missing(path)
        HakumiORM::TaskOutput.seed_missing(path)
      end

      sig { override.params(path: String).void }
      def seed_loaded(path)
        HakumiORM::TaskOutput.seed_loaded(path)
      end

      sig { override.params(path: String, table_count: Integer).void }
      def fixtures_loaded(path:, table_count:)
        HakumiORM::TaskOutput.fixtures_loaded(path: path, table_count: table_count)
      end

      sig do
        override
          .params(path: String, table_count: Integer, row_count: Integer, table_rows: T::Hash[String, Integer])
          .void
      end
      def fixtures_dry_run(path:, table_count:, row_count:, table_rows:)
        HakumiORM::TaskOutput.fixtures_dry_run(
          path: path,
          table_count: table_count,
          row_count: row_count,
          table_rows: table_rows
        )
      end

      sig { override.params(table_name: String, lines: T::Array[String]).void }
      def associations_for_table(table_name, lines)
        HakumiORM::TaskOutput.associations_for_table(table_name, lines)
      end
    end
  end
end
