# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    module SqlGenerator
      extend T::Sig

      PG_TYPES = T.let({
        string: "varchar(255)", text: "text", integer: "integer", bigint: "bigint",
        float: "double precision", decimal: "decimal", boolean: "boolean",
        date: "date", datetime: "timestamp", timestamp: "timestamp",
        binary: "bytea", json: "json", jsonb: "jsonb", uuid: "uuid",
        inet: "inet", cidr: "cidr", hstore: "hstore",
        integer_array: "integer[]", string_array: "text[]",
        float_array: "double precision[]", boolean_array: "boolean[]"
      }.freeze, T::Hash[Symbol, String])

      MYSQL_TYPES = T.let({
        string: "varchar(255)", text: "text", integer: "int", bigint: "bigint",
        float: "double", decimal: "decimal", boolean: "tinyint(1)",
        date: "date", datetime: "datetime", timestamp: "timestamp",
        binary: "blob", json: "json", jsonb: "json", uuid: "char(36)",
        inet: "varchar(45)", cidr: "varchar(45)", hstore: "json"
      }.freeze, T::Hash[Symbol, String])

      SQLITE_TYPES = T.let({
        string: "TEXT", text: "TEXT", integer: "INTEGER", bigint: "INTEGER",
        float: "REAL", decimal: "REAL", boolean: "INTEGER",
        date: "TEXT", datetime: "TEXT", timestamp: "TEXT",
        binary: "BLOB", json: "TEXT", jsonb: "TEXT", uuid: "TEXT",
        inet: "TEXT", cidr: "TEXT", hstore: "TEXT"
      }.freeze, T::Hash[Symbol, String])

      ARRAY_TYPES = T.let(
        %i[integer_array string_array float_array boolean_array].freeze,
        T::Array[Symbol]
      )

      IDENTIFIER_LIMITS = T.let({
        postgresql: 63,
        mysql: 64,
        sqlite: nil
      }.freeze, T::Hash[Symbol, T.nilable(Integer)])

      sig { params(type: Symbol, dialect: Dialect::Base, limit: T.nilable(Integer), precision: T.nilable(Integer), scale: T.nilable(Integer)).returns(String) }
      def self.column_type_sql(type, dialect, limit: nil, precision: nil, scale: nil)
        if ARRAY_TYPES.include?(type) && dialect.name != :postgresql
          raise HakumiORM::Error, "Array columns are only supported on PostgreSQL"
        end

        base = type_map(dialect).fetch(type) do
          raise HakumiORM::Error, "Unknown column type: #{type}"
        end

        if type == :string && limit
          "varchar(#{limit})"
        elsif type == :decimal && precision
          scale ? "decimal(#{precision},#{scale})" : "decimal(#{precision})"
        else
          base
        end
      end

      sig { params(table_def: TableDefinition, dialect: Dialect::Base, inline_fks: T::Array[T::Hash[Symbol, String]]).returns(String) }
      def self.create_table(table_def, dialect, inline_fks: [])
        parts = build_column_parts(table_def, dialect)
        inline_fks.each { |fk| parts << fk_clause(fk, dialect) }
        "CREATE TABLE #{quote_id(dialect, table_def.name)} (#{parts.join(", ")})"
      end

      sig { params(table_def: TableDefinition, dialect: Dialect::Base).returns(T::Array[String]) }
      def self.build_column_parts(table_def, dialect)
        parts = T.let([], T::Array[String])
        parts << "#{quote_id(dialect, "id")} #{pk_type_sql(table_def.id_type, dialect)}" if table_def.id_type && table_def.id_type != false
        table_def.columns.each { |col| parts << column_sql(col, dialect) }

        cpk = table_def.composite_primary_key
        if cpk && !cpk.empty?
          pk_cols = cpk.map { |c| quote_id(dialect, c) }.join(", ")
          parts << "PRIMARY KEY (#{pk_cols})"
        end
        parts
      end

      sig { params(foreign_key: T::Hash[Symbol, String], dialect: Dialect::Base).returns(String) }
      def self.fk_clause(foreign_key, dialect)
        col = quote_id(dialect, foreign_key.fetch(:column))
        ref_table = quote_id(dialect, foreign_key.fetch(:to_table))
        ref_pk = quote_id(dialect, foreign_key.fetch(:primary_key))
        "FOREIGN KEY (#{col}) REFERENCES #{ref_table} (#{ref_pk})"
      end

      sig { params(table_def: TableDefinition, dialect: Dialect::Base).returns(T::Array[String]) }
      def self.create_table_with_fks(table_def, dialect)
        if dialect.name == :sqlite
          sqls = [create_table(table_def, dialect, inline_fks: table_def.foreign_keys)]
        else
          sqls = [create_table(table_def, dialect)]
          table_def.foreign_keys.each do |fk|
            sqls << add_foreign_key(
              table_def.name, fk.fetch(:to_table),
              column: fk.fetch(:column), dialect: dialect, primary_key: fk.fetch(:primary_key)
            )
          end
        end
        sqls
      end

      sig { params(name: String, dialect: Dialect::Base).returns(String) }
      def self.drop_table(name, dialect)
        "DROP TABLE #{quote_id(dialect, name)}"
      end

      sig { params(old_name: String, new_name: String, dialect: Dialect::Base).returns(String) }
      def self.rename_table(old_name, new_name, dialect)
        "ALTER TABLE #{quote_id(dialect, old_name)} RENAME TO #{quote_id(dialect, new_name)}"
      end

      sig { params(table: String, col: ColumnDefinition, dialect: Dialect::Base).returns(String) }
      def self.add_column(table, col, dialect)
        "ALTER TABLE #{quote_id(dialect, table)} ADD COLUMN #{column_sql(col, dialect)}"
      end

      sig { params(table: String, col_name: String, dialect: Dialect::Base).returns(String) }
      def self.remove_column(table, col_name, dialect)
        "ALTER TABLE #{quote_id(dialect, table)} DROP COLUMN #{quote_id(dialect, col_name)}"
      end

      sig { params(table: String, col: ColumnDefinition, dialect: Dialect::Base).returns(String) }
      def self.change_column(table, col, dialect)
        type_sql = column_type_sql(col.type, dialect, limit: col.limit, precision: col.precision, scale: col.scale)
        "ALTER TABLE #{quote_id(dialect, table)} ALTER COLUMN #{quote_id(dialect, col.name)} TYPE #{type_sql}"
      end

      sig { params(table: String, old_name: String, new_name: String, dialect: Dialect::Base).returns(String) }
      def self.rename_column(table, old_name, new_name, dialect)
        "ALTER TABLE #{quote_id(dialect, table)} RENAME COLUMN #{quote_id(dialect, old_name)} TO #{quote_id(dialect, new_name)}"
      end

      sig { params(table: String, columns: T::Array[String], dialect: Dialect::Base, unique: T::Boolean, name: T.nilable(String)).returns(String) }
      def self.add_index(table, columns, dialect:, unique: false, name: nil)
        idx_name = name || "idx_#{table}_#{columns.join("_")}"
        validate_identifier_length!(idx_name, dialect, "Index name")
        col_list = columns.map { |c| quote_id(dialect, c) }.join(", ")
        prefix = unique ? "CREATE UNIQUE INDEX" : "CREATE INDEX"
        "#{prefix} #{quote_id(dialect, idx_name)} ON #{quote_id(dialect, table)} (#{col_list})"
      end

      sig { params(table: String, columns: T::Array[String], dialect: Dialect::Base, name: T.nilable(String)).returns(String) }
      def self.remove_index(table, columns, dialect:, name: nil)
        idx_name = name || "idx_#{table}_#{columns.join("_")}"
        validate_identifier_length!(idx_name, dialect, "Index name")
        "DROP INDEX #{quote_id(dialect, idx_name)}"
      end

      sig { params(from_table: String, to_table: String, column: String, dialect: Dialect::Base, primary_key: String, on_delete: T.nilable(Symbol)).returns(String) }
      def self.add_foreign_key(from_table, to_table, column:, dialect:, primary_key: "id", on_delete: nil)
        fk_name = "fk_#{from_table}_#{column}"
        validate_identifier_length!(fk_name, dialect, "Foreign key name")
        ref = "REFERENCES #{quote_id(dialect, to_table)} (#{quote_id(dialect, primary_key)})"
        fk_clause = "FOREIGN KEY (#{quote_id(dialect, column)}) #{ref}"
        sql = "ALTER TABLE #{quote_id(dialect, from_table)} ADD CONSTRAINT #{quote_id(dialect, fk_name)} #{fk_clause}"
        sql += " ON DELETE CASCADE" if on_delete == :cascade
        sql += " ON DELETE SET NULL" if on_delete == :set_null
        sql += " ON DELETE RESTRICT" if on_delete == :restrict
        sql
      end

      sig { params(from_table: String, to_table: String, dialect: Dialect::Base, column: T.nilable(String)).returns(String) }
      def self.remove_foreign_key(from_table, to_table, dialect:, column: nil)
        col = column || "#{singularize(to_table)}_id"
        fk_name = "fk_#{from_table}_#{col}"
        "ALTER TABLE #{quote_id(dialect, from_table)} DROP CONSTRAINT #{quote_id(dialect, fk_name)}"
      end

      sig { params(dialect: Dialect::Base, name: String).returns(String) }
      private_class_method def self.quote_id(dialect, name)
        dialect.quote_id(name)
      end

      sig { params(identifier: String, dialect: Dialect::Base, kind: String).void }
      private_class_method def self.validate_identifier_length!(identifier, dialect, kind)
        limit = IDENTIFIER_LIMITS[dialect.name]
        return unless limit
        return if identifier.length <= limit

        raise HakumiORM::Error,
              "#{kind} '#{identifier}' exceeds #{dialect.name} identifier limit (#{identifier.length}/#{limit} chars)"
      end

      sig { params(col: ColumnDefinition, dialect: Dialect::Base).returns(String) }
      private_class_method def self.column_sql(col, dialect)
        type_sql = column_type_sql(col.type, dialect, limit: col.limit, precision: col.precision, scale: col.scale)
        parts = [quote_id(dialect, col.name), type_sql]
        parts << "NOT NULL" unless col.null
        parts << "DEFAULT #{col.default}" if col.default
        parts.join(" ")
      end

      sig { params(id_type: T.any(Symbol, FalseClass), dialect: Dialect::Base).returns(String) }
      private_class_method def self.pk_type_sql(id_type, dialect)
        case id_type
        when :bigserial then bigserial_pk(dialect)
        when :uuid then "uuid PRIMARY KEY"
        when :serial then serial_pk(dialect)
        else raise HakumiORM::Error, "Unknown PK type: #{id_type}"
        end
      end

      sig { params(dialect: Dialect::Base).returns(String) }
      private_class_method def self.bigserial_pk(dialect)
        case dialect.name
        when :postgresql then "bigserial PRIMARY KEY"
        when :mysql then "bigint AUTO_INCREMENT PRIMARY KEY"
        when :sqlite then "INTEGER PRIMARY KEY AUTOINCREMENT"
        else raise HakumiORM::Error, "Unknown dialect: #{dialect.name}"
        end
      end

      sig { params(dialect: Dialect::Base).returns(String) }
      private_class_method def self.serial_pk(dialect)
        case dialect.name
        when :postgresql then "serial PRIMARY KEY"
        when :mysql then "int AUTO_INCREMENT PRIMARY KEY"
        when :sqlite then "INTEGER PRIMARY KEY AUTOINCREMENT"
        else raise HakumiORM::Error, "Unknown dialect: #{dialect.name}"
        end
      end

      sig { params(dialect: Dialect::Base).returns(T::Hash[Symbol, String]) }
      private_class_method def self.type_map(dialect)
        case dialect.name
        when :postgresql then PG_TYPES
        when :mysql then MYSQL_TYPES
        when :sqlite then SQLITE_TYPES
        else raise HakumiORM::Error, "Unknown dialect: #{dialect.name}"
        end
      end

      sig { params(word: String).returns(String) }
      private_class_method def self.singularize(word)
        if word.end_with?("ies")
          "#{word.delete_suffix("ies")}y"
        elsif word.end_with?("ses", "xes", "zes", "ches", "shes")
          word.delete_suffix("es")
        elsif word.end_with?("s") && !word.end_with?("ss", "us", "is")
          word.delete_suffix("s")
        else
          word
        end
      end
    end
  end
end
