# HakumiORM -- Architecture Reference

All source code lives under `lib/hakumi_orm/`. Every file is Sorbet `typed: strict`. One class per file, except `sealed!` hierarchies (`Bind`, `Expr`) where all subclasses must be co-located for exhaustive `T.absurd` checks.

## Top-Level API

| File | Module / Class | Description |
|---|---|---|
| `hakumi_orm.rb` | `HakumiORM` | Entry point. Provides `configure(&blk)`, `config`, `adapter`, `adapter=`, `reset_config!`. All generated code defaults to `HakumiORM.adapter`. |
| `errors.rb` | `Errors` | Collects validation messages grouped by field. Methods: `add(field, message)`, `valid?`, `messages`, `full_messages`, `count`. |
| `validation_error.rb` | `ValidationError < Error` | Wraps `Errors` for the type-state flow. Raised when contract validation fails. |
| `stale_object_error.rb` | `StaleObjectError < Error` | Raised by optimistic locking when `lock_version` doesn't match. |
| `configuration.rb` | `Configuration` | Global config object. Attributes: `adapter_name`, `database`, `host`, `port`, `username`, `password`, `output_dir`, `models_dir`, `contracts_dir`, `module_name`, `adapter`, `pool_size`, `pool_timeout`. Builds the adapter lazily from connection params. |
| `json.rb` | `Json`, `JsonScalar` | Opaque JSON wrapper storing raw JSON string. `Json.parse(raw)` from PG, `Json.from_hash(h)` / `Json.from_array(a)` from Ruby. Navigation: `[](key)` and `at(index)` return `T.nilable(Json)`. Typed extractors: `as_s`, `as_i`, `as_f`, `as_bool`, `scalar`. Zero `Object`, zero `T.untyped`. |
| `tasks.rb` | `Tasks` | Rake tasks for HakumiORM. `require "hakumi_orm/tasks"` adds `rake hakumi:generate`. |
| `version.rb` | `VERSION` | Gem version constant. |

## Query Engine

| File | Module / Class | Description |
|---|---|---|
| `bind.rb` | `Bind` (abstract, sealed) | Base class for typed bind parameters. All subclasses co-located in this file for `sealed!`: `IntBind`, `StrBind`, `FloatBind`, `DecimalBind`, `BoolBind`, `TimeBind`, `DateBind`, `JsonBind`, `NullBind`. Each implements `pg_value` to serialize its value for the wire protocol. |
| `field_ref.rb` | `FieldRef` | Holds column metadata (`name`, `table_name`, `column_name`, `qualified_name`). Provides `asc`/`desc` for ordering. |
| `order_clause.rb` | `OrderClause` | Value object: `FieldRef` + `:asc` / `:desc` direction. |
| `join_clause.rb` | `JoinClause` | Value object: `join_type` (`:inner`, `:left`, `:right`, `:cross`) + `target_table` + `source_field` + `target_field`. |
| `assignment.rb` | `Assignment` | Value object: `FieldRef` + `Bind` pair for `UPDATE SET` expressions and `update_all`. |
| `field.rb` | `Field[ValueType]` (abstract, generic) | Base for typed field constants. Exposes `eq`, `neq`, `in_list`, `not_in_list`, `is_null`, `is_not_null`. Operator aliases: `==` (`eq`), `!=` (`neq`). |
| `field/comparable_field.rb` | `ComparableField` | Adds `gt`, `gte`, `lt`, `lte`, `between` with operator aliases `>`, `>=`, `<`, `<=`. |
| `field/text_field.rb` | `TextField` | Adds `like`, `ilike`. |
| `field/int_field.rb` | `IntField` | Integer field (`ComparableField`). |
| `field/float_field.rb` | `FloatField` | Float field (`ComparableField`). |
| `field/decimal_field.rb` | `DecimalField` | BigDecimal field (`ComparableField`). |
| `field/str_field.rb` | `StrField` | String/UUID field (`TextField`). |
| `field/bool_field.rb` | `BoolField` | Boolean field (base `Field`, no comparison/text ops). |
| `field/time_field.rb` | `TimeField` | Time/timestamp field (`ComparableField`). |
| `field/date_field.rb` | `DateField` | Date field (`ComparableField`). |
| `field/json_field.rb` | `JsonField` | JSON/JSONB field (base `Field`). |
| `expr.rb` | `Expr` (abstract, sealed) | Expression tree for WHERE clauses. All subclasses co-located in this file for `sealed!`: `Predicate` (leaf node with field + operator + binds), `AndExpr`, `OrExpr`, `NotExpr`, `RawExpr` (raw SQL fragment with `?` placeholders), `SubqueryExpr` (field + `:in`/`:not_in` + `CompiledQuery`). Supports `and`, `or`, `not` composition. Operator aliases: `&` (`and`), `|` (`or`), `!` (`not`). |
| `cast.rb` | `Cast` | Converts raw database strings to Ruby types: `to_integer`, `to_float`, `to_decimal`, `to_boolean`, `to_time`, `to_date`, `to_string`, `to_json`. |
| `compiled_query.rb` | `CompiledQuery` | Immutable container holding a SQL string and its associated `T::Array[Bind]`. Provides `pg_params` to extract serialized values. |
| `sql_compiler.rb` | `SqlCompiler` | Compiles `Expr` trees, ordering, joins, limit/offset, DISTINCT, GROUP BY, HAVING, LOCK, and aggregate functions into parameterized SQL. Generates `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXISTS`, `AGGREGATE` with sequential bind markers. All values go through bind parameters, never interpolated. |
| `sql_compiler_expr.rb` | `SqlCompiler` (reopened) | Expression compilation methods extracted for ClassLength: `compile_expr`, `compile_binary`, `compile_predicate`, `compile_simple_op`, `compile_list_op`, `compile_between`, `compile_raw_expr`, `compile_subquery_expr`, `rebase_binds`. |
| `preload_node.rb` | `PreloadNode`, `PreloadSpec` | Type-safe preload specification. `PreloadSpec = T.any(Symbol, T::Hash[Symbol, T.any(Symbol, T::Array[Symbol])])`. `PreloadNode` normalizes specs into a tree for nested preloading: `.preload(:posts, comments: :author)`. |
| `relation.rb` | `Relation[ModelType]` (abstract, generic) | Fluent query builder with mutable chaining: `where`, `where_raw`, `order`, `order_by`, `limit`, `offset`, `distinct`, `group`, `having`, `lock`, `join`, `preload`. Subclasses implement `hydrate` to materialize rows. Terminal methods: `to_a`, `first`, `count`, `exists?`, `pluck_raw`, `delete_all`, `update_all`, `to_sql`, `sum`, `average`, `minimum`, `maximum`, `pluck`. Provides `compile(dialect)` for obtaining a `CompiledQuery` without an adapter. |
| `relation_query.rb` | `Relation` (reopened) | Aggregate, pluck, and expression helper methods extracted for ClassLength: `sum`, `average`, `minimum`, `maximum`, `pluck`, `run_aggregate`, `build_pluck_rows`, `combine_exprs`. |

## Adapter Layer

| File | Module / Class | Description |
|---|---|---|
| `adapter.rb` | *(barrel)* | Requires `adapter/result` and `adapter/base`. |
| `adapter/result.rb` | `Adapter::Result` (abstract) | Abstract result interface. `get_value(row, col)` returns `T.nilable(String)` for nullable columns. `fetch_value(row, col)` returns `String` and raises on unexpected NULL. Also defines `row_count`, `values`, `column_values`, `affected_rows`, `close`. |
| `adapter/base.rb` | `Adapter::Base` (abstract) | Abstract database connection. Defines `exec_params(sql, params)`, `exec(sql)`, `close`, `transaction(requires_new:, &blk)`. Returns the associated `Dialect::Base`. Supports nested transactions via savepoints (SAVEPOINT/RELEASE/ROLLBACK TO) when `requires_new: true`. |
| `adapter/postgresql.rb` | `Adapter::Postgresql` | PostgreSQL implementation wrapping `PG::Connection`. |
| `adapter/postgresql_result.rb` | `Adapter::PostgresqlResult` | Wraps `PG::Result`. |
| `adapter/mysql.rb` | `Adapter::Mysql` | MySQL implementation wrapping `Mysql2::Client`. Uses `T.unsafe` at 2 splat FFI points where `mysql2`'s C extension API requires dynamic splatting incompatible with Sorbet strict. |
| `adapter/mysql_result.rb` | `Adapter::MysqlResult` | MySQL result wrapper (rows as `T::Array[T::Array[T.nilable(String)]]` + `affected_rows`). |
| `adapter/sqlite.rb` | `Adapter::Sqlite` | SQLite implementation wrapping `SQLite3::Database`. Uses `bind_each` helper to bind parameters individually (avoids splat). |
| `adapter/sqlite_result.rb` | `Adapter::SqliteResult` | SQLite result wrapper. |
| `adapter/connection_pool.rb` | `Adapter::ConnectionPool` | Thread-safe connection pool. Creates connections lazily up to `size`. Reentrant: nested calls within the same thread reuse the same connection. Timeout raises `Adapter::TimeoutError`. Implements `Adapter::Base` — transparent drop-in. |
| `adapter/timeout_error.rb` | `Adapter::TimeoutError < Error` | Raised when the connection pool times out waiting for an available connection. |

## Dialect Layer

| File | Module / Class | Description |
|---|---|---|
| `dialect.rb` | `Dialect::Base` (abstract) | Interface for database-specific SQL syntax: `bind_marker(index)`, `quote_id(name)`, `qualified_name(table, column)`, `supports_returning?`, `name`. |
| `dialect/postgresql.rb` | `Dialect::Postgresql` | PostgreSQL: `$1`/`$2` bind markers, double-quote identifiers, caches quoted/qualified names. |
| `dialect/mysql.rb` | `Dialect::Mysql` | MySQL: `?` bind markers, backtick identifiers, `supports_returning?: false`. |
| `dialect/sqlite.rb` | `Dialect::Sqlite` | SQLite: `?` bind markers, double-quote identifiers, `supports_returning?: true`. |

## Code Generation

| File | Module / Class | Description |
|---|---|---|
| `codegen.rb` | *(barrel)* | Requires all codegen modules. |
| `codegen/hakumi_type.rb` | `Codegen::HakumiType` | `T::Enum` representing the internal type system: `Integer`, `String`, `Boolean`, `Timestamp`, `Date`, `Float`, `Decimal`, `Json`, `Uuid`. Methods: `ruby_type`, `ruby_type_string(nullable:)`, `field_class`, `comparable?`, `text?`, `bind_class`. All branches use `T.absurd` for exhaustiveness. |
| `codegen/type_map.rb` | `Codegen::TypeMap` | Resolves a database column type (e.g. `"varchar"`, `"int4"`) to a `HakumiType` using dialect-specific maps. Also generates cast expressions for code generation. |
| `codegen/type_maps/postgresql.rb` | `Codegen::TypeMaps::Postgresql` | Maps PostgreSQL data types (`int4`, `text`, `bool`, `timestamptz`, ...) to `HakumiType`. |
| `codegen/type_maps/mysql.rb` | `Codegen::TypeMaps::Mysql` | Maps MySQL data types (`int`, `varchar`, `tinyint`, `datetime`, ...) to `HakumiType`. |
| `codegen/type_maps/sqlite.rb` | `Codegen::TypeMaps::Sqlite` | Maps SQLite data types (`INTEGER`, `TEXT`, `REAL`, ...) to `HakumiType`. |
| `codegen/column_info.rb` | `Codegen::ColumnInfo` | `T::Struct` with column metadata: `name`, `data_type`, `udt_name`, `nullable`, `default`, `max_length`. |
| `codegen/foreign_key_info.rb` | `Codegen::ForeignKeyInfo` | `T::Struct` with FK metadata: `column_name`, `foreign_table`, `foreign_column`. |
| `codegen/table_info.rb` | `Codegen::TableInfo` | Table metadata: `name`, `columns`, `foreign_keys`, `unique_columns`, `primary_key`. `unique_columns` drives `has_one` vs `has_many` detection. |
| `codegen/template_local.rb` | `Codegen::TemplateLocal` | Type aliases for template variables: `TemplateScalar`, `TemplateCollection`, `TemplateLocal`, `BelongsToEntry`. |
| `codegen/schema_reader.rb` | `Codegen::SchemaReader` | PostgreSQL schema reader. Reads `information_schema` to extract tables, columns, primary keys, unique columns, and foreign keys. |
| `codegen/mysql_schema_reader.rb` | `Codegen::MysqlSchemaReader` | MySQL schema reader. Reads `information_schema` with MySQL-specific queries. Handles `tinyint(1)` → `Boolean`. |
| `codegen/sqlite_schema_reader.rb` | `Codegen::SqliteSchemaReader` | SQLite schema reader. Uses `PRAGMA table_info`, `PRAGMA index_list`, `PRAGMA foreign_key_list`. |
| `codegen/generator.rb` | `Codegen::Generator` | Generates `typed: strict` Ruby files from ERB templates. Uses folder-per-table structure: `checkable.rb`, `schema.rb`, `record.rb`, `new_record.rb`, `validated_record.rb`, `base_contract.rb`, `relation.rb`, plus a manifest. Generates `has_many`, `has_one` (UNIQUE FK), `has_many :through` (FK chains / join tables), and `belongs_to` associations from foreign keys. Nested preload support via `PreloadNode`. `dependent: :delete_all / :destroy` on `delete!`. Auto-detects `created_at`/`updated_at` timestamp columns. |
| `codegen/generator_validation.rb` | `Codegen::Generator` (reopened) | Validation, persistence, and variant builder methods: `build_checkable`, `build_validated_record`, `build_base_contract`, `build_contract`, `build_variant_base`, `build_update_locals`, `build_delete_locals`, `build_update_sql`, `build_update_bind_list`, `timestamp_auto_column?`, `to_h_value_type`, `generate_contracts!`, `lock_version_column`. Optimistic locking: detects `lock_version` column and modifies UPDATE SQL/binds accordingly. |
| `codegen/generator_assoc.rb` | `Codegen::Generator` (reopened) | Association builder methods: `compute_has_many_through`, `build_has_many_assocs`, `build_has_one_assocs`, `build_belongs_to_assocs`, `build_has_many_through_assocs`, `collect_join_table_throughs`, `collect_chain_throughs`, `assoc_delete_sql`. |

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
    │   ├── column_info.rb
    │   ├── foreign_key_info.rb
    │   ├── generator.rb
    │   ├── generator_assoc.rb
    │   ├── generator_validation.rb
    │   ├── hakumi_type.rb
    │   ├── mysql_schema_reader.rb
    │   ├── schema_reader.rb
    │   ├── sqlite_schema_reader.rb
    │   ├── table_info.rb
    │   ├── template_local.rb
    │   ├── type_map.rb
    │   └── type_maps/
    │       ├── mysql.rb
    │       ├── postgresql.rb
    │       └── sqlite.rb
    ├── compiled_query.rb
    ├── configuration.rb
    ├── dialect.rb
    ├── dialect/
    │   ├── mysql.rb
    │   ├── postgresql.rb
    │   └── sqlite.rb
    ├── errors.rb
    ├── expr.rb
    ├── field.rb
    ├── field/
    │   ├── bool_field.rb
    │   ├── comparable_field.rb
    │   ├── date_field.rb
    │   ├── decimal_field.rb
    │   ├── float_field.rb
    │   ├── int_field.rb
    │   ├── json_field.rb
    │   ├── str_field.rb
    │   ├── text_field.rb
    │   └── time_field.rb
    ├── field_ref.rb
    ├── join_clause.rb
    ├── json.rb
    ├── order_clause.rb
    ├── preload_node.rb
    ├── relation.rb
    ├── relation_query.rb
    ├── sql_compiler.rb
    ├── sql_compiler_expr.rb
    ├── stale_object_error.rb
    ├── tasks.rb
    ├── validation_error.rb
    └── version.rb
```
