# typed: strict
# frozen_string_literal: true

require "digest"

module HakumiORM
  class Migration
    module SchemaFingerprint
      extend T::Sig

      DRIFT_ENV_VAR = "HAKUMI_ALLOW_SCHEMA_DRIFT"
      GENERATOR_VERSION = "1"

      sig { params(expected: String, actual: String).void }
      def self.check!(expected, actual)
        return if expected == actual

        if drift_allowed?
          logger = HakumiORM.config.logger
          logger&.warn("HakumiORM: Schema drift detected but bypassed via #{DRIFT_ENV_VAR}.")
          return
        end

        raise SchemaDriftError.new(expected, actual)
      end

      sig { returns(T::Boolean) }
      def self.drift_allowed?
        ENV.key?(DRIFT_ENV_VAR)
      end

      sig { params(tables: T::Hash[String, Codegen::TableInfo]).returns(String) }
      def self.compute(tables)
        buf = "V:#{GENERATOR_VERSION}\n"

        tables.keys.sort.each do |table_name|
          table = tables.fetch(table_name)
          append_table(buf, table_name, table)
        end

        Digest::SHA256.hexdigest(buf)
      end

      sig { params(buf: String, table_name: String, table: Codegen::TableInfo).void }
      private_class_method def self.append_table(buf, table_name, table)
        buf << "T:#{table_name}|PK:#{table.primary_key}\n"

        table.columns.sort_by(&:name).each do |col|
          buf << "C:#{col.name}|#{col.data_type}|#{col.nullable}|#{col.default}\n"
        end

        table.foreign_keys.sort_by { |fk| [fk.column_name, fk.foreign_table, fk.foreign_column] }.each do |fk|
          buf << "FK:#{fk.column_name}->#{fk.foreign_table}.#{fk.foreign_column}\n"
        end

        table.unique_columns.sort.each do |uc|
          buf << "UQ:#{uc}\n"
        end
      end
    end
  end
end
