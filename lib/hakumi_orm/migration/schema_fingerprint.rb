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

      SCHEMA_META_TABLE = "hakumi_schema_meta"

      CREATE_META_SQL = T.let(<<~SQL, String)
        CREATE TABLE IF NOT EXISTS hakumi_schema_meta (
          fingerprint varchar(64) NOT NULL,
          schema_data text NOT NULL,
          generator_version varchar(20) NOT NULL
        )
      SQL

      sig { params(tables: T::Hash[String, Codegen::TableInfo]).returns(String) }
      def self.build_canonical(tables)
        buf = "V:#{GENERATOR_VERSION}\n"

        tables.keys.sort.each do |table_name|
          table = tables.fetch(table_name)
          append_table(buf, table_name, table)
        end

        buf
      end

      sig { params(tables: T::Hash[String, Codegen::TableInfo]).returns(String) }
      def self.compute(tables)
        Digest::SHA256.hexdigest(build_canonical(tables))
      end

      sig { params(adapter: Adapter::Base, fingerprint: String, canonical: String).void }
      def self.store!(adapter, fingerprint, canonical)
        adapter.exec(CREATE_META_SQL).close
        adapter.transaction do |_txn|
          adapter.exec("DELETE FROM #{SCHEMA_META_TABLE}").close
          d = adapter.dialect
          sql = "INSERT INTO #{SCHEMA_META_TABLE} (fingerprint, schema_data, generator_version) " \
                "VALUES (#{d.bind_marker(0)}, #{d.bind_marker(1)}, #{d.bind_marker(2)})"
          result = adapter.exec_params(sql, [fingerprint, canonical, GENERATOR_VERSION])
          result.close
        end
      end

      sig { params(adapter: Adapter::Base).returns(T.nilable(String)) }
      def self.read_from_db(adapter)
        result = T.let(nil, T.nilable(Adapter::Result))
        result = adapter.exec("SELECT fingerprint FROM #{SCHEMA_META_TABLE} LIMIT 1")
        return nil if result.row_count.zero?

        result.get_value(0, 0)&.to_s
      rescue StandardError
        nil
      ensure
        result&.close
      end

      sig { params(adapter: Adapter::Base).returns(T.nilable(String)) }
      def self.read_canonical_from_db(adapter)
        result = T.let(nil, T.nilable(Adapter::Result))
        result = adapter.exec("SELECT schema_data FROM #{SCHEMA_META_TABLE} LIMIT 1")
        return nil if result.row_count.zero?

        result.get_value(0, 0)&.to_s
      rescue StandardError
        nil
      ensure
        result&.close
      end

      MIGRATION_FILE_RE = T.let(/\A(\d{14})_\w+\.rb\z/, Regexp)

      sig { params(adapter: Adapter::Base, migrations_path: String).returns(T::Array[String]) }
      def self.pending_migrations(adapter, migrations_path)
        return [] unless Dir.exist?(migrations_path)

        applied = read_applied_versions(adapter)
        file_versions = scan_file_versions(migrations_path)
        file_versions - applied
      end

      sig { params(adapter: Adapter::Base).returns(T::Array[String]) }
      def self.read_applied_versions(adapter)
        result = T.let(nil, T.nilable(Adapter::Result))
        result = adapter.exec("SELECT version FROM hakumi_migrations ORDER BY version")
        versions = T.let([], T::Array[String])
        i = T.let(0, Integer)
        while i < result.row_count
          versions << result.fetch_value(i, 0)
          i += 1
        end
        versions
      rescue StandardError
        []
      ensure
        result&.close
      end

      sig { params(path: String).returns(T::Array[String]) }
      def self.scan_file_versions(path)
        Dir.children(path).filter_map do |f|
          match = f.match(MIGRATION_FILE_RE)
          match ? match[1] : nil
        end.sort
      end

      sig { params(stored: String, live: String).returns(T::Array[String]) }
      def self.diff_canonical(stored, live)
        stored_tables = parse_canonical(stored)
        live_tables = parse_canonical(live)
        all_table_names = (stored_tables.keys + live_tables.keys).uniq.sort
        lines = T.let([], T::Array[String])

        all_table_names.each do |tname|
          old_lines = stored_tables[tname] || []
          new_lines = live_tables[tname] || []
          table_diff = diff_table(tname, old_lines, new_lines)
          lines.concat(table_diff) unless table_diff.empty?
        end

        lines
      end

      sig { params(canonical: String).returns(T::Hash[String, T::Array[String]]) }
      private_class_method def self.parse_canonical(canonical)
        result = T.let({}, T::Hash[String, T::Array[String]])
        current_table = T.let(nil, T.nilable(String))

        canonical.each_line do |line|
          stripped = line.chomp
          next if stripped.start_with?("V:")

          if stripped.start_with?("T:")
            current_table = stripped.split("|").first&.delete_prefix("T:")
            result[current_table] = [stripped] if current_table
          elsif current_table
            (result[current_table] ||= []) << stripped
          end
        end

        result
      end

      sig { params(table_name: String, old_lines: T::Array[String], new_lines: T::Array[String]).returns(T::Array[String]) }
      private_class_method def self.diff_table(table_name, old_lines, new_lines)
        old_set = old_lines.to_set
        new_set = new_lines.to_set
        return [] if old_set == new_set

        removed = (old_set - new_set).sort
        added = (new_set - old_set).sort
        lines = T.let(["#{table_name}:"], T::Array[String])

        removed.each { |l| lines << "  - #{format_line(l)}" }
        added.each { |l| lines << "  + #{format_line(l)}" }

        lines
      end

      sig { params(line: String).returns(String) }
      private_class_method def self.format_line(line)
        case line
        when /\AC:(\w+)\|([^|]+)\|(\w+)\|([^|]*)(?:\|EV:(.+))?\z/
          null_str = Regexp.last_match(3) == "true" ? "nullable" : "not null"
          default_str = Regexp.last_match(4).to_s.empty? ? "" : ", default: #{Regexp.last_match(4)}"
          enum_str = Regexp.last_match(5) ? ", enum: [#{Regexp.last_match(5)}]" : ""
          "#{Regexp.last_match(1)} (#{Regexp.last_match(2)}, #{null_str}#{default_str}#{enum_str})"
        when /\AFK:(\w+)->(\w+)\.(\w+)\z/
          "FK: #{Regexp.last_match(1)} -> #{Regexp.last_match(2)}.#{Regexp.last_match(3)}"
        when /\AUQ:(\w+)\z/
          "UNIQUE: #{Regexp.last_match(1)}"
        when /\AT:(\w+)\|PK:(.+)\z/
          "table #{Regexp.last_match(1)} (PK: #{Regexp.last_match(2)})"
        else
          line
        end
      end

      sig { params(buf: String, col: Codegen::ColumnInfo).void }
      private_class_method def self.append_column(buf, col)
        buf << "C:#{col.name}|#{col.data_type}|#{col.nullable}|#{col.default}"
        ev = col.enum_values
        buf << "|EV:#{ev.join(",")}" if ev && !ev.empty?
        buf << "\n"
      end

      sig { params(buf: String, table_name: String, table: Codegen::TableInfo).void }
      private_class_method def self.append_table(buf, table_name, table)
        buf << "T:#{table_name}|PK:#{table.primary_key}\n"

        table.columns.sort_by(&:name).each { |col| append_column(buf, col) }

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
