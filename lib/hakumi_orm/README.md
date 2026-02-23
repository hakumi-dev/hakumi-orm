# HakumiORM -- Architecture Reference

All source code lives under "lib/hakumi_orm/". Every file is Sorbet "typed: strict". One class per file, except "sealed!" hierarchies ("Bind", "Expr") where all subclasses must be co-located for exhaustive "T.absurd" checks.

## Top-Level API

| File | Module / Class | Description |
|---|---|---|
| "hakumi_orm.rb" | "HakumiORM" | Entry point. Provides "configure(&blk)", "config", "adapter(name = nil)", "adapter=", "using(name, &blk)", "reset_config!", "define_enums(table, &blk)", "associate(table, &blk)". "adapter" checks thread-local override first (set by "using"), then falls back to primary. All generated code defaults to "HakumiORM.adapter". |
| "errors.rb" | "Errors" | Collects validation messages grouped by field. Methods: "add(field, message)", "valid?", "messages", "full_messages", "count". |
| "validation_error.rb" | "ValidationError < Error" | Wraps "Errors" for the type-state flow. Raised when contract validation fails. |
| "stale_object_error.rb" | "StaleObjectError < Error" | Raised by optimistic locking when "lock_version" doesn't match. |
| "database_config.rb" | "DatabaseConfig < T::Struct" | Connection parameters for a single database: "adapter_name", "database", "host", "port", "username", "password", "pool_size", "pool_timeout", "connection_options". |
| "database_url_parser.rb" | "DatabaseUrlParser" | Parses "database_url" strings ("postgresql://user:pass@host:5432/db?sslmode=require") into "DatabaseConfig". Supports "postgresql://", "postgres://", "mysql2://", "mysql://", "sqlite3://", "sqlite://" schemes. Decodes percent-encoded passwords, extracts query params into "connection_options". |
| "database_config_builder.rb" | "DatabaseConfigBuilder" | Mutable builder for "DatabaseConfig". Used inside "Configuration#database_config" blocks. Supports "database_url=" (delegates to "DatabaseUrlParser") or individual field setters. Validates adapter_name and requires database. |
| "loggable.rb" | "Loggable" | Sorbet "interface!" for loggers. Defines five abstract methods: "debug", "info", "warn", "error", "fatal" (each accepts optional message string + block). "::Logger" includes "Loggable" at boot via runtime mixin, so it satisfies the contract out of the box. RBI shim ("sorbet/rbi/shims/logger.rbi") declares the inclusion for Sorbet static analysis. Any custom logger can "include HakumiORM::Loggable" to be accepted by "Configuration#logger=". |
| "configuration.rb" | "Configuration" | Global config object. Primary attributes: "adapter_name", "database", "host", "port", "username", "password", "output_dir", "models_dir", "contracts_dir", "module_name", "adapter", "pool_size", "pool_timeout", "logger" ("T.nilable(Loggable)"), "migrations_path", "associations_path", "enums_path", "connection_options", "database_url=". "log_level=" creates an internal "Logger" to "$stdout" with the given level (":debug", ":info", ":warn", ":error", ":fatal"). Multi-DB: "database_config(name, &blk)" registers named databases, "adapter_for(name)" lazily builds adapters, "named_database(name)" returns config, "database_names" lists names, "register_adapter(name, adapter)" for manual injection, "close_named_adapters!" cleanup. "connection_options" stores extra driver params (sslmode, connect_timeout, etc.) extracted from URL query params. Boot checks: "verify_schema_fingerprint!(adapter)" compares manifest fingerprint with DB; "verify_no_pending_migrations!(adapter)" checks for unapplied migrations (bypass with HAKUMI_SKIP_MIGRATION_CHECK=1). |
| "json.rb" | "Json", "JsonScalar" | Opaque JSON wrapper storing raw JSON string. "Json.parse(raw)" from PG, "Json.from_hash(h)" / "Json.from_array(a)" from Ruby. Navigation: "[](key)" and "at(index)" return "T.nilable(Json)". Typed extractors: "as_s", "as_i", "as_f", "as_bool", "scalar". Zero "Object", zero "T.untyped". |
| "setup_generator.rb" | "SetupGenerator" | Creates initial project structure. "new(root:, framework:)" accepts ":rails", ":sinatra", or ":standalone". "run!" creates directories ("db/migrate", "db/associations", "db/generated") and config initializer. Rails adds "app/models", "app/contracts", writes to "config/initializers/hakumi/orm.rb". Standalone/Sinatra writes to "config/hakumi/orm.rb" with "require" and Rakefile instructions. Namespaced under "hakumi/" to coexist with other Hakumi packages. Idempotent: skips existing files/dirs. Returns "{ created:, skipped: }". |
| "tasks.rb" | "Tasks" | Rake tasks for HakumiORM. "require "hakumi_orm/tasks"" adds: "hakumi:install" (setup generator), "hakumi:generate" (generate + annotate), "hakumi:migrate", "hakumi:rollback[N]", "hakumi:migrate:status", "hakumi:version", "hakumi:migration[name]", "hakumi:type[name]", "hakumi:associations" (list all associations). |
| "framework.rb" | "Framework" | Framework detection and integration registry. "register(name, &detector)" adds a framework, "detect" returns first matching name (or ":standalone"), "current" / "current=" tracks active framework. Query methods: "rails?", "sinatra?", "standalone?". "registered" lists names, "reset!" clears state. |
| "framework/rails_config.rb" | "Framework::RailsConfig" | Testable Rails defaults. "apply_defaults(config, logger:)" sets "models_dir", "contracts_dir", logger without requiring Rails. |
| "framework/rails.rb" | "Framework::Rails < Rails::Railtie" | Rails Railtie ("typed: false", Sorbet-ignored). Initializers: "hakumi_orm.configure" (sets current, applies defaults), "hakumi_orm.load_generated" (loads manifest, then models/contracts sorted by path depth for correct variant loading order). Loads rake tasks. |
| "framework/sinatra_config.rb" | "Framework::SinatraConfig" | Testable Sinatra defaults. "apply_defaults(config, root:, logger:)" sets path defaults relative to root. |
| "framework/sinatra.rb" | "Framework::Sinatra" | Sinatra extension ("typed: false", Sorbet-ignored). "registered(app)" callback reads "root" and "logger" from settings, applies defaults. User registers via "register HakumiORM::Framework::Sinatra". |
| "version.rb" | "VERSION" | Gem version constant. |

## Query Engine

| File | Module / Class | Description |
|---|---|---|
| "bind.rb" | "Bind" (abstract, sealed) | Base class for typed bind parameters. All subclasses co-located in this file for "sealed!": "IntBind", "StrBind", "FloatBind", "DecimalBind", "BoolBind", "TimeBind", "DateBind", "JsonBind", "NullBind", "IntArrayBind", "StrArrayBind", "FloatArrayBind", "BoolArrayBind". Zero "T.untyped" -- custom types reuse existing Bind subclasses (e.g., Money -> "DecimalBind"). Array binds serialize to PG array literal format ("{1,2,3}"). "StrArrayBind" always quotes non-NULL values to handle curly braces, newlines, tabs, and all edge cases. |
| "field_ref.rb" | "FieldRef" | Holds column metadata ("name", "table_name", "column_name", "qualified_name"). Provides "asc"/"desc" for ordering. |
| "order_clause.rb" | "OrderClause" | Value object: "FieldRef" + ":asc" / ":desc" direction. |
| "join_clause.rb" | "JoinClause" | Value object: "join_type" (":inner", ":left", ":right", ":cross") + "target_table" + "source_field" + "target_field". |
| "assignment.rb" | "Assignment" | Value object: "FieldRef" + "Bind" pair for "UPDATE SET" expressions and "update_all". |
| "field.rb" | "Field[ValueType]" (abstract, generic) | Base for typed field constants. Exposes "eq", "neq", "in_list", "not_in_list", "is_null", "is_not_null". Operator aliases: "==" ("eq"), "!=" ("neq"). |
| "field/comparable_field.rb" | "ComparableField" | Adds "gt", "gte", "lt", "lte", "between" with operator aliases ">", ">=", "<", "<=". |
| "field/text_field.rb" | "TextField" | Adds "like", "ilike". |
| "field/int_field.rb" | "IntField" | Integer field ("ComparableField"). |
| "field/float_field.rb" | "FloatField" | Float field ("ComparableField"). |
| "field/decimal_field.rb" | "DecimalField" | BigDecimal field ("ComparableField"). |
| "field/str_field.rb" | "StrField" | String/UUID field ("TextField"). |
| "field/bool_field.rb" | "BoolField" | Boolean field (base "Field", no comparison/text ops). |
| "field/time_field.rb" | "TimeField" | Time/timestamp field ("ComparableField"). |
| "field/date_field.rb" | "DateField" | Date field ("ComparableField"). |
| "field/json_field.rb" | "JsonField" | JSON/JSONB field (base "Field"). |
| "field/enum_field.rb" | "EnumField" | PG enum field (base "Field"). Serializes "T::Enum" values to "StrBind". |
| "field/int_array_field.rb" | "IntArrayField" | Integer array field (base "Field"). Supports "eq", "is_null", "is_not_null". |
| "field/str_array_field.rb" | "StrArrayField" | String array field (base "Field"). |
| "field/float_array_field.rb" | "FloatArrayField" | Float array field (base "Field"). |
| "field/bool_array_field.rb" | "BoolArrayField" | Boolean array field (base "Field"). |
| "expr.rb" | "Expr" (abstract, sealed) | Expression tree for WHERE clauses. All subclasses co-located in this file for "sealed!": "Predicate" (leaf node with field + operator + binds), "AndExpr", "OrExpr", "NotExpr", "RawExpr" (raw SQL fragment with "?" placeholders, SQL-aware counting via "SQL_QUOTED_OR_PLACEHOLDER" regex that skips "?" inside string literals, identifiers, and comments), "SubqueryExpr" (field + ":in"/":not_in" + "CompiledQuery"). Supports "and", "or", "not" composition. Operator aliases: "&" ("and"), "|" ("or"), "!" ("not"). |
| "cast.rb" | "Cast" | Converts raw database strings to Ruby types: "to_integer", "to_float", "to_decimal", "to_boolean", "to_time", "to_date", "to_string", "to_json", "to_int_array", "to_str_array", "to_float_array", "to_bool_array". Array methods parse PG array literal format ("{1,2,NULL,3}") with proper handling of quoted strings and NULL elements. |
| "compiled_query.rb" | "CompiledQuery" | Immutable container holding a SQL string and its associated "T::Array[Bind]". Provides "pg_params" to extract serialized values. |
| "sql_compiler.rb" | "SqlCompiler" | Compiles "Expr" trees, ordering, joins, limit/offset, DISTINCT, GROUP BY, HAVING, LOCK, and aggregate functions into parameterized SQL. Generates "SELECT", "INSERT", "UPDATE", "DELETE", "EXISTS", "AGGREGATE" with sequential bind markers. All values go through bind parameters, never interpolated. |
| "sql_compiler_expr.rb" | "SqlCompiler" (reopened) | Expression compilation methods extracted for ClassLength: "compile_expr", "compile_binary", "compile_predicate", "compile_simple_op", "compile_list_op", "compile_between", "compile_raw_expr" (SQL-aware "?" replacement via "RawExpr::SQL_QUOTED_OR_PLACEHOLDER"), "compile_subquery_expr", "rebase_binds" (SQL-aware "$N" rebasing via "SQL_QUOTED_OR_BIND_MARKER"). Both methods skip placeholders inside single-quoted strings, double-quoted identifiers, line comments, and block comments. |
| "preload_node.rb" | "PreloadNode", "PreloadSpec" | Type-safe preload specification. "PreloadSpec = T.any(Symbol, T::Hash[Symbol, T.any(Symbol, T::Array[Symbol])])". "PreloadNode" normalizes specs into a tree for nested preloading: ".preload(:posts, comments: :author)". |
| "relation.rb" | "Relation[ModelType]" (abstract, generic) | Fluent query builder with mutable chaining: "where", "where_raw", "order", "order_by", "limit", "offset", "distinct", "group", "having", "lock", "join", "preload". Subclasses implement "hydrate" to materialize rows. Terminal methods: "to_a", "first", "count", "exists?", "pluck_raw", "delete_all", "update_all", "to_sql", "sum", "average", "minimum", "maximum", "pluck". Provides "compile(dialect)" for obtaining a "CompiledQuery" without an adapter. "overridable" "custom_preload(name, records, adapter)" (no-op by default) -- users override in their Relation to handle non-FK associations. Generated "run_preloads" dispatches known (FK-based) associations via "case" and delegates unknown names to "custom_preload". Depth guard: "MAX_PRELOAD_DEPTH = 8" prevents runaway recursion from circular preload nodes. "initialize_copy" deep-copies all internal arrays for safe "dup"/"clone" reuse. |
| "relation_query.rb" | "Relation" (reopened) | Aggregate, pluck, and expression helper methods extracted for ClassLength: "sum", "average", "minimum", "maximum", "pluck", "run_aggregate", "build_pluck_rows", "combine_exprs". |

## Adapter Layer

| File | Module / Class | Description |
|---|---|---|
| "adapter.rb" | *(barrel)* | Requires "adapter/result" and "adapter/base". |
| "adapter/result.rb" | "Adapter::Result" (abstract) | Abstract result interface. "get_value(row, col)" returns "T.nilable(String)" for nullable columns. "fetch_value(row, col)" returns "String" and raises on unexpected NULL. Also defines "row_count", "values", "column_values", "affected_rows", "close". |
| "adapter/base.rb" | "Adapter::Base" (abstract) | Abstract database connection. Defines "exec_params(sql, params)", "exec(sql)", "prepare(name, sql)", "exec_prepared(name, params)", "prepare_exec(name, sql, params)" (prepare + execute atomically — overridden by ConnectionPool for same-connection affinity), "close", "transaction(requires_new:, &blk)". Returns the associated "Dialect::Base". Supports nested transactions via savepoints (SAVEPOINT/RELEASE/ROLLBACK TO) when "requires_new: true". Transaction hooks: "after_commit(&blk)" and "after_rollback(&blk)" register deferred callbacks using a "@tx_frames" stack (one frame per BEGIN/SAVEPOINT). On RELEASE SAVEPOINT, child-frame "after_commit" callbacks merge into the parent. On ROLLBACK TO SAVEPOINT, child-frame "after_commit" callbacks are discarded and "after_rollback" callbacks fire immediately. On top-level COMMIT/ROLLBACK, all accumulated callbacks fire. All transaction control results (BEGIN, COMMIT, ROLLBACK, SAVEPOINT, RELEASE) are closed immediately after use. Private helpers: "log_query_start" / "log_query_done(sql, params, start)" for SQL query logging with timing via "Configuration#logger" ("T.nilable(Loggable)"). |
| "adapter/postgresql.rb" | "Adapter::Postgresql" | PostgreSQL implementation wrapping "PG::Connection". |
| "adapter/postgresql_result.rb" | "Adapter::PostgresqlResult" | Wraps "PG::Result". |
| "adapter/mysql.rb" | "Adapter::Mysql" | MySQL implementation wrapping "Mysql2::Client". Uses "T.unsafe" at 2 splat FFI points where "mysql2"'s C extension API requires dynamic splatting incompatible with Sorbet strict. |
| "adapter/mysql_result.rb" | "Adapter::MysqlResult" | MySQL result wrapper (rows as "T::Array[T::Array[T.nilable(String)]]" + "affected_rows"). |
| "adapter/sqlite.rb" | "Adapter::Sqlite" | SQLite implementation wrapping "SQLite3::Database". Uses "bind_each" helper to bind parameters individually (avoids splat). |
| "adapter/sqlite_result.rb" | "Adapter::SqliteResult" | SQLite result wrapper. |
| "adapter/connection_pool.rb" | "Adapter::ConnectionPool" | Thread-safe connection pool. Creates connections lazily up to "size". Reentrant: nested calls within the same thread reuse the same connection. Timeout raises "Adapter::TimeoutError". Dead connection eviction: on query error, checks "conn.alive?" and discards dead connections via "discard" (closes, decrements "@total", signals waiting threads). Overrides "prepare_exec" to guarantee prepare + execute run on the same physical connection within a single checkout. Overrides "after_commit"/"after_rollback" to forward to the thread's checked-out connection via "checked_out_connection!". Implements "Adapter::Base" — works anywhere a single adapter is expected, no code changes needed. |
| "adapter/timeout_error.rb" | "Adapter::TimeoutError < Error" | Raised when the connection pool times out waiting for an available connection. |

## Dialect Layer

| File | Module / Class | Description |
|---|---|---|
| "dialect.rb" | "Dialect::Base" (abstract) | Interface for database-specific SQL syntax: "bind_marker(index)", "quote_id(name)", "qualified_name(table, column)", "supports_returning?", "supports_ddl_transactions?", "supports_advisory_lock?", "advisory_lock_sql", "advisory_unlock_sql", "name". |
| "dialect/postgresql.rb" | "Dialect::Postgresql" | PostgreSQL: "$1"/"$2" bind markers, double-quote identifiers, DDL transactions supported, advisory lock via "pg_advisory_lock". |
| "dialect/mysql.rb" | "Dialect::Mysql" | MySQL: "?" bind markers, backtick identifiers, "supports_returning?: false", DDL transactions NOT supported (implicit commit), advisory lock via "GET_LOCK". |
| "dialect/sqlite.rb" | "Dialect::Sqlite" | SQLite: "?" bind markers, double-quote identifiers, "supports_returning?: true", DDL transactions supported, no advisory lock (single-process). |

## Code Generation

| File | Module / Class | Description |
|---|---|---|
| "codegen.rb" | *(barrel)* | Requires all codegen modules. |
| "codegen/hakumi_type.rb" | "Codegen::HakumiType" | "T::Enum" representing the internal type system: "Integer", "String", "Boolean", "Timestamp", "Date", "Float", "Decimal", "Json", "Uuid", "IntegerArray", "StringArray", "FloatArray", "BooleanArray". Methods: "ruby_type", "ruby_type_string(nullable:)", "field_class", "comparable?", "text?", "array_type?", "bind_class". All branches use "T.absurd" for exhaustiveness. |
| "codegen/type_map.rb" | "Codegen::TypeMap" | Resolves a database column type (e.g. ""varchar"", ""int4"", ""_int4"") to a "HakumiType" using dialect-specific maps. Lookup priority: "udt_name" first, then "data_type", then "String" fallback. Also generates cast expressions for code generation. |
| "codegen/type_registry.rb" | "Codegen::TypeRegistry" | User-defined custom type registration. "register(name:, ruby_type:, cast_expression:, field_class:, bind_class:)" to define a type. "map_pg_type(udt_name, name)" to link PG types. "resolve_pg(udt_name)" to look up. "reset!" for test isolation. Raises "ArgumentError" on duplicate registration. |
| "codegen/type_scaffold.rb" | "Codegen::TypeScaffold" | Generates boilerplate files for custom types: a Field subclass (using existing Bind subclasses, zero "T.untyped") and a TypeRegistry registration file. Does not overwrite existing files. Invoked via "rake hakumi:type[name]". |
| "codegen/type_maps/postgresql.rb" | "Codegen::TypeMaps::Postgresql" | Maps PostgreSQL data types ("int4", "text", "bool", "timestamptz", ...) to "HakumiType". |
| "codegen/type_maps/mysql.rb" | "Codegen::TypeMaps::Mysql" | Maps MySQL data types ("int", "varchar", "tinyint", "datetime", ...) to "HakumiType". |
| "codegen/type_maps/sqlite.rb" | "Codegen::TypeMaps::Sqlite" | Maps SQLite data types ("INTEGER", "TEXT", "REAL", ...) to "HakumiType". |
| "codegen/column_info.rb" | "Codegen::ColumnInfo" | "T::Struct" with column metadata: "name", "data_type", "udt_name", "nullable", "default", "max_length". |
| "codegen/foreign_key_info.rb" | "Codegen::ForeignKeyInfo" | "T::Struct" with FK metadata: "column_name", "foreign_table", "foreign_column". |
| "codegen/table_info.rb" | "Codegen::TableInfo" | Table metadata: "name", "columns", "foreign_keys", "unique_columns", "primary_key". "unique_columns" drives "has_one" vs "has_many" detection. |
| "codegen/template_local.rb" | "Codegen::TemplateLocal" | Type aliases for template variables: "TemplateScalar", "TemplateCollection", "TemplateLocal", "BelongsToEntry". |
| "codegen/schema_reader.rb" | "Codegen::SchemaReader" | PostgreSQL schema reader. Reads "information_schema" to extract tables, columns, primary keys, unique columns, and foreign keys. |
| "codegen/mysql_schema_reader.rb" | "Codegen::MysqlSchemaReader" | MySQL schema reader. Reads "information_schema" with MySQL-specific queries. Handles "tinyint(1)" → "Boolean". |
| "codegen/sqlite_schema_reader.rb" | "Codegen::SqliteSchemaReader" | SQLite schema reader. Uses "PRAGMA table_info", "PRAGMA index_list", "PRAGMA foreign_key_list". |
| "codegen/generator_options.rb" | "Codegen::GeneratorOptions" | "T::Struct" configuring code generation: "dialect", "output_dir", "module_name", "models_dir", "contracts_dir", "soft_delete_tables", "created_at_column", "updated_at_column", "custom_associations", "user_enums", "internal_tables". "custom_associations" maps table name to "CustomAssociation" arrays. "user_enums" maps table name to "EnumDefinition" arrays. |
| "codegen/custom_association.rb" | "Codegen::CustomAssociation" | "T::Struct" declaring a non-FK association: "name", "target_table", "foreign_key", "primary_key", "kind" (":has_many" / ":has_one"), "order_by" (optional, for deterministic ":has_one"). Constants: "VALID_KINDS", "VALID_NAME_PATTERN". |
| "codegen/enum_definition.rb" | "Codegen::EnumDefinition" | "T::Struct" for user-defined enum metadata: "column_name", "values" (key-value hash), "prefix", "suffix". Methods: "serialized_values", "db_type" (detects integer vs string from first value). |
| "codegen/enum_builder.rb" | "Codegen::EnumBuilder" | DSL builder for "HakumiORM.define_enums" blocks. "enum(column, prefix:, suffix:, **values)" builds "EnumDefinition" structs. |
| "codegen/enum_loader.rb" | "Codegen::EnumLoader" | Loads all "*.rb" files from "enums_path", executes them (which calls "HakumiORM.define_enums"), and returns "T::Hash[String, T::Array[EnumDefinition]]". |
| "codegen/association_builder.rb" | "Codegen::AssociationBuilder" | DSL builder for "HakumiORM.associate" blocks. Methods: "has_many(name, target:, foreign_key:, primary_key:)" and "has_one(...)". Builds "CustomAssociation" structs. |
| "codegen/association_loader.rb" | "Codegen::AssociationLoader" | Loads all "*.rb" files from "associations_path", executes them (which calls "HakumiORM.associate"), and returns the resulting "T::Hash[String, T::Array[CustomAssociation]]". |
| "codegen/model_annotator.rb" | "Codegen::ModelAnnotator" | Updates model files with "# == Schema Information ==" / "# == End Schema Information ==" annotation blocks showing table name, primary key, columns (with enum types), enum details (class, values, predicates), and all associations (FK, custom, through). Replaces existing blocks or prepends if no markers found. Inner "Context < T::Struct" holds all data needed to build annotations. |
| "codegen/generator.rb" | "Codegen::Generator" | Generates "typed: strict" Ruby files from ERB templates. Uses folder-per-table structure: "checkable.rb", "schema.rb", "record.rb", "new_record.rb", "validated_record.rb", "base_contract.rb", "relation.rb", plus a manifest. Generates "has_many", "has_one" (UNIQUE FK), "has_many :through" (FK chains / join tables), and "belongs_to" associations from foreign keys. Custom associations (from config) are merged into the same hash format and produce identical generated code. Nested preload support via "PreloadNode". Generated "run_preloads" dispatches FK-based and custom associations, then falls through to "custom_preload" for escape-hatch associations. "dependent: :delete_all / :destroy" on "delete!". Auto-detects "created_at"/"updated_at" timestamp columns. Lifecycle hooks: "record.rb.tt" calls "Contract.on_destroy" before DELETE and "Contract.after_destroy" after, "Contract.after_update" after UPDATE; "validated_record.rb.tt" calls "Contract.after_create" after INSERT; "base_contract.rb.tt" generates stubs for all 8 hooks ("on_all", "on_create", "on_update", "on_persist", "on_destroy", "after_create", "after_update", "after_destroy"). Model annotations: after generating all files, updates model files with a "# == Schema Information ==" comment block showing columns, types, and all associations (FK + custom + through). |
| "codegen/generator_validation.rb" | "Codegen::Generator" (reopened) | Validation, persistence, and variant builder methods: "build_checkable", "build_validated_record", "build_base_contract", "build_contract", "build_variant_base", "build_update_locals", "build_delete_locals", "build_update_sql", "build_update_bind_list", "timestamp_auto_column?", "to_h_value_type", "generate_contracts!", "lock_version_column". "enum_bind_expr" selects "IntBind" or "StrBind" based on "@integer_backed_enums". "json_expr"/"json_ruby_type" return Integer for integer-backed enum serialization. Optimistic locking: detects "lock_version" column and modifies UPDATE SQL/binds accordingly. |
| "codegen/generator_enum.rb" | "Codegen::Generator" (reopened) | Enum type handling: "collect_enum_types" reads PG native + user-defined enum definitions, generates "T::Enum" classes with proper serialization ("new(0)" for integer-backed, "new("admin")" for string-backed). "build_enum_predicates" generates predicate method data (prefix/suffix). "inject_user_enums!" injects user-defined enums into "ColumnInfo" with column type validation ("ENUM_COMPATIBLE_TYPES" + "ENUM_TYPE_COHERENCE"), and populates "@integer_backed_enums" set. "build_cast_lines" coerces ".to_i" for integer-backed enums on "deserialize". |
| "codegen/generator_assoc.rb" | "Codegen::Generator" (reopened) | FK association builder methods: "compute_has_many_through", "build_has_many_assocs", "build_has_one_assocs", "build_belongs_to_assocs", "build_has_many_through_assocs", "collect_join_table_throughs", "collect_chain_throughs", "assoc_delete_sql", "annotate_models!". |
| "codegen/generator_custom_assoc.rb" | "Codegen::Generator" (reopened) | Custom association validation and builder methods: "validate_custom_assocs!" (11 validations: kind, name format, table/column existence, non-null source key, type compatibility via "HakumiType#compatible_with?", name collisions). "build_custom_has_many", "build_custom_has_one", "build_custom_assoc_hash", "build_fk_assoc_names". |
| "migration.rb" | "Migration" | Base class for user-defined migrations. Class method "disable_ddl_transaction!" opts out of transaction wrapping (needed for "CREATE INDEX CONCURRENTLY"). Instance DSL methods: "create_table", "drop_table", "rename_table", "add_column", "remove_column", "change_column", "rename_column", "add_index", "remove_index", "add_foreign_key", "remove_foreign_key", "execute". All DSL methods close the result handle after execution. Receives adapter in constructor, delegates to "SqlGenerator" for dialect-specific SQL. Migration registry uses "T.cast" (not "T.unsafe") in "inherited" to store subclass references. |
| "migration/column_definition.rb" | "Migration::ColumnDefinition" | "T::Struct" with column metadata: "name", "type" (Symbol), "null", "default", "limit", "precision", "scale". |
| "migration/table_definition.rb" | "Migration::TableDefinition" | Collects columns during "create_table" block. Type-specific sugar methods ("t.string", "t.integer", etc.), "t.timestamps", "t.references(table, column: nil)" with explicit column override for irregular plurals. "t.primary_key(cols)" for composite primary keys. Validates column types early against "VALID_TYPES" (raises with full list on unknown type). Tracks inline foreign keys. |
| "migration/sql_generator.rb" | "Migration::SqlGenerator" | Converts DSL operations to dialect-specific SQL. Type maps for PG, MySQL, SQLite. Handles PK types (":bigserial", ":uuid", ":serial"), column constraints, indexes, foreign keys with ON DELETE. Validates auto-generated identifier names against dialect-specific limits ("IDENTIFIER_LIMITS": PG 63, MySQL 64). Appends "PRIMARY KEY (col1, col2)" for composite primary keys. |
| "migration/runner.rb" | "Migration::Runner" | Loads migration files from "migrations_path", tracks applied versions in "hakumi_migrations" table. "migrate!" runs pending, "rollback!(count:)" reverses N migrations, "status" reports up/down state, "current_version" returns latest. Wraps each migration AND its version bookkeeping (INSERT/DELETE into "hakumi_migrations") in the same transaction when dialect supports DDL transactions; logs warning otherwise. Respects "disable_ddl_transaction!". Acquires dialect-specific advisory lock before migrate!/rollback! to prevent concurrent execution (released in ensure block). Advisory lock and DDL results are closed immediately after use. Filename pattern restricted to "\w+" for safety. Clear error messages for class name mismatches, syntax errors, and invalid inheritance. Inner "FileInfo < T::Struct" (version, name, filename) provides typed access to migration file metadata -- zero "T.must" on hash lookups. |
| "migration/file_generator.rb" | "Migration::FileGenerator" | Generates timestamped migration file (e.g., "20260222120000_create_users.rb") with empty "up"/"down" methods. Validates migration names against "VALID_NAME_PATTERN" ("/\A[a-z]\w*\z/") -- rejects hyphens, spaces, leading digits, empty names. Prevents duplicate names. Bumps timestamp by 1 second on collision with existing files. |
| "migration/schema_fingerprint.rb" | "Migration::SchemaFingerprint" | Computes deterministic SHA256 hash of schema. Prefixed with GENERATOR_VERSION to detect codegen changes. Sorts tables and columns alphabetically. Includes column types, nullability, defaults, PG native enum values, foreign keys, unique columns. "check!" compares two fingerprints: raises "SchemaDriftError" on mismatch (or warns if HAKUMI_ALLOW_SCHEMA_DRIFT is set). "drift_allowed?" checks env var. "pending_migrations(adapter, path)" compares migration files against applied versions. "read_applied_versions(adapter)" reads from "hakumi_migrations". "scan_file_versions(path)" extracts versions from migration filenames. "build_canonical(tables)" produces deterministic schema string. "store!(adapter, fingerprint, canonical)" persists to "hakumi_schema_meta" (DELETE + INSERT wrapped in a transaction for atomicity). "diff_canonical(stored, live)" produces line-by-line diff. |
| "schema_drift_error.rb" | "SchemaDriftError" | Raised when boot fingerprint does not match DB. Message includes truncated fingerprints and remediation commands. Bypassed via HAKUMI_ALLOW_SCHEMA_DRIFT=1 env var (emergency only). |
| "pending_migration_error.rb" | "PendingMigrationError < Error" | Raised when boot check detects unapplied migration files. Lists pending versions (up to 5) and remediation instructions. Bypassed via HAKUMI_SKIP_MIGRATION_CHECK=1 env var. |
| "schema_drift_checker.rb" | "SchemaDriftChecker" | Encapsulates schema integrity checks. Class method "read_schema(config, adapter)" reads live schema. Instance methods: "update_fingerprint!" stores live fingerprint in DB, "check" returns array of issue descriptions (pending migrations + schema drift with line-by-line diff). Used by "hakumi:check" task. |
| "scaffold_generator.rb" | "ScaffoldGenerator" | Creates model stub + contract for a table. Singularizes table name, supports "module_name", skips existing files. Invoked via "rake hakumi:scaffold[table]". |

## File Tree

```
lib/
├── hakumi_orm.rb
└── hakumi_orm/
    ├── adapter.rb
    ├── adapter/
    │   ├── base.rb
    │   ├── connection_pool.rb
    │   ├── mysql.rb
    │   ├── mysql_result.rb
    │   ├── postgresql.rb
    │   ├── postgresql_result.rb
    │   ├── result.rb
    │   ├── sqlite.rb
    │   ├── sqlite_result.rb
    │   └── timeout_error.rb
    ├── assignment.rb
    ├── bind.rb
    ├── cast.rb
    ├── codegen.rb
    ├── codegen/
    │   ├── association_builder.rb
    │   ├── association_loader.rb
    │   ├── column_info.rb
    │   ├── custom_association.rb
    │   ├── enum_builder.rb
    │   ├── enum_definition.rb
    │   ├── enum_loader.rb
    │   ├── foreign_key_info.rb
    │   ├── generator.rb
    │   ├── generator_assoc.rb
    │   ├── generator_custom_assoc.rb
    │   ├── generator_enum.rb
    │   ├── generator_options.rb
    │   ├── generator_validation.rb
    │   ├── hakumi_type.rb
    │   ├── model_annotator.rb
    │   ├── mysql_schema_reader.rb
    │   ├── schema_reader.rb
    │   ├── sqlite_schema_reader.rb
    │   ├── table_info.rb
    │   ├── template_local.rb
    │   ├── type_map.rb
    │   ├── type_registry.rb
    │   ├── type_scaffold.rb
    │   └── type_maps/
    │       ├── mysql.rb
    │       ├── postgresql.rb
    │       └── sqlite.rb
    ├── compiled_query.rb
    ├── configuration.rb
    ├── database_config.rb
    ├── database_config_builder.rb
    ├── database_url_parser.rb
    ├── dialect.rb
    ├── dialect/
    │   ├── mysql.rb
    │   ├── postgresql.rb
    │   └── sqlite.rb
    ├── errors.rb
    ├── expr.rb
    ├── field.rb
    ├── framework.rb
    ├── framework/
    │   ├── rails.rb
    │   ├── rails_config.rb
    │   ├── sinatra.rb
    │   └── sinatra_config.rb
    ├── field/
    │   ├── bool_array_field.rb
    │   ├── bool_field.rb
    │   ├── comparable_field.rb
    │   ├── date_field.rb
    │   ├── decimal_field.rb
    │   ├── enum_field.rb
    │   ├── float_array_field.rb
    │   ├── float_field.rb
    │   ├── int_array_field.rb
    │   ├── int_field.rb
    │   ├── json_field.rb
    │   ├── str_array_field.rb
    │   ├── str_field.rb
    │   ├── text_field.rb
    │   └── time_field.rb
    ├── field_ref.rb
    ├── join_clause.rb
    ├── json.rb
    ├── loggable.rb
    ├── order_clause.rb
    ├── preload_node.rb
    ├── relation.rb
    ├── relation_query.rb
    ├── sql_compiler.rb
    ├── sql_compiler_expr.rb
    ├── migration.rb
    ├── migration/
    │   ├── column_definition.rb
    │   ├── file_generator.rb
    │   ├── runner.rb
    │   ├── schema_fingerprint.rb
    │   ├── sql_generator.rb
    │   └── table_definition.rb
    ├── pending_migration_error.rb
    ├── scaffold_generator.rb
    ├── schema_drift_checker.rb
    ├── schema_drift_error.rb
    ├── setup_generator.rb
    ├── stale_object_error.rb
    ├── tasks.rb
    ├── validation_error.rb
    └── version.rb
```
