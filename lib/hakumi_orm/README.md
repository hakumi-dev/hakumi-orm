# HakumiORM -- Architecture Reference

All source code lives under `lib/hakumi_orm/`. Every file is Sorbet `typed: strict`.

## Top-Level API

| File | Module / Class | Description |
|---|---|---|
| `hakumi_orm.rb` | `HakumiORM` | Entry point. Provides `configure(&blk)`, `config`, `adapter`, `adapter=`, `reset_config!`. All generated code defaults to `HakumiORM.adapter`. |
| `errors.rb` | `Errors`, `ValidationError` | `Errors` collects validation messages grouped by field. `ValidationError < Error` wraps `Errors` for the type-state flow (`New -> Validated -> Record`). |
| `configuration.rb` | `Configuration` | Global config object. Attributes: `adapter_name`, `database`, `host`, `port`, `username`, `password`, `output_dir`, `models_dir`, `contracts_dir`, `module_name`, `adapter`. Builds the adapter lazily from connection params. |

## Query Engine

| File | Module / Class | Description |
|---|---|---|
| `bind.rb` | `Bind` (abstract, sealed) | Base class for typed bind parameters. Subclasses: `IntBind`, `StrBind`, `FloatBind`, `DecimalBind`, `BoolBind`, `TimeBind`, `DateBind`, `NullBind`. Each implements `pg_value` to serialize its value for the PostgreSQL wire protocol. |
| `field_ref.rb` | `FieldRef` | Holds column metadata (`name`, `table_name`, `column_name`, `qualified_name`). Provides `asc`/`desc` for ordering. Also defines `OrderClause`, `JoinClause`, and `Assignment` value objects. |
| `field.rb` | `Field[ValueType]` (abstract, generic) | Base for typed field constants. Exposes `eq`, `neq`, `in_list`, `not_in_list`, `is_null`, `is_not_null`. Operator aliases: `==` (`eq`), `!=` (`neq`). Concrete subclasses: `IntField`, `FloatField`, `DecimalField`, `StrField`, `BoolField`, `TimeField`, `DateField`. `ComparableField` adds `gt`, `gte`, `lt`, `lte`, `between` with operator aliases `>`, `>=`, `<`, `<=`. `TextField` adds `like`, `ilike`. |
| `expr.rb` | `Expr` (abstract, sealed) | Expression tree for WHERE clauses. Subclasses: `Predicate` (leaf node with field + operator + binds), `AndExpr`, `OrExpr`, `NotExpr`, `RawExpr` (raw SQL fragment with `?` placeholders), `SubqueryExpr` (field + `:in`/`:not_in` + `CompiledQuery`). Supports `and`, `or`, `not` composition with deterministic parentheses. Operator aliases: `&` (`and`), `\|` (`or`), `!` (`not`) -- all delegate to the named methods. |
| `cast.rb` | `Cast` | Converts raw PostgreSQL strings to Ruby types: `to_integer`, `to_float`, `to_decimal`, `to_boolean`, `to_time`, `to_date`, `to_string`. |
| `compiled_query.rb` | `CompiledQuery` | Immutable container holding a SQL string and its associated `T::Array[Bind]`. Provides `pg_params` to extract serialized values. |
| `sql_compiler.rb` | `SqlCompiler` | Compiles `Expr` trees, ordering, joins, limit/offset, DISTINCT, GROUP BY, HAVING, LOCK, and aggregate functions into parameterized SQL. Generates `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXISTS`, `AGGREGATE` with sequential bind markers. All values go through bind parameters, never interpolated. |
| `sql_compiler_expr.rb` | `SqlCompiler` (reopened) | Expression compilation methods extracted for ClassLength: `compile_expr`, `compile_binary`, `compile_predicate`, `compile_simple_op`, `compile_list_op`, `compile_between`, `compile_raw_expr`, `compile_subquery_expr`, `rebase_binds`. |
| `relation.rb` | `Relation[ModelType]` (abstract, generic) | Fluent query builder with mutable chaining: `where`, `where_raw`, `order`, `order_by`, `limit`, `offset`, `distinct`, `group`, `having`, `lock`, `join`, `preload`. Subclasses implement `hydrate` to materialize rows. Terminal methods: `to_a`, `first`, `count`, `exists?`, `pluck_raw`, `delete_all`, `update_all`, `to_sql`, `sum`, `average`, `minimum`, `maximum`, `pluck`. Provides `compile(dialect)` for obtaining a `CompiledQuery` without an adapter. |
| `relation_query.rb` | `Relation` (reopened) | Aggregate, pluck, and expression helper methods extracted from Relation for ClassLength: `sum`, `average`, `minimum`, `maximum`, `pluck`, `run_aggregate`, `build_pluck_rows`, `combine_exprs`. |

## Adapter Layer

| File | Module / Class | Description |
|---|---|---|
| `adapter.rb` | `Adapter::Result` (abstract) | Abstract result interface. `get_value(row, col)` returns `T.nilable(String)` for nullable columns. `fetch_value(row, col)` returns `String` and raises on unexpected NULL. Also defines `row_count`, `values`, `column_values`, `affected_rows`, `close`. |
| `adapter.rb` | `Adapter::Base` (abstract) | Abstract database connection. Defines `exec_params(sql, params)`, `exec(sql)`, `close`, `transaction(&blk)`. Returns the associated `Dialect::Base`. |
| `adapter/postgresql.rb` | `Adapter::Postgresql` | PostgreSQL implementation wrapping `PG::Connection`. `Adapter::PostgresqlResult` wraps `PG::Result`. |

## Dialect Layer

| File | Module / Class | Description |
|---|---|---|
| `dialect.rb` | `Dialect::Base` (abstract) | Interface for database-specific SQL syntax: `bind_marker(index)`, `quote_id(name)`, `qualified_name(table, column)`, `supports_returning?`, `name`. |
| `dialect/postgresql.rb` | `Dialect::Postgresql` | PostgreSQL implementation. Uses `$1`, `$2` bind markers. Quotes identifiers with double quotes. Caches quoted identifiers and qualified names for zero repeated allocations. |

## Code Generation

| File | Module / Class | Description |
|---|---|---|
| `codegen/hakumi_type.rb` | `Codegen::HakumiType` | `T::Enum` representing the internal type system: `Integer`, `String`, `Boolean`, `Timestamp`, `Date`, `Float`, `Decimal`. Methods: `ruby_type`, `ruby_type_string(nullable:)`, `field_class`, `comparable?`, `text?`. All branches use `T.absurd` for exhaustiveness. |
| `codegen/type_map.rb` | `Codegen::TypeMap` | Resolves a database column type (e.g. `"varchar"`, `"int4"`) to a `HakumiType` using dialect-specific maps. Also generates cast expressions for code generation. |
| `codegen/type_maps/postgresql.rb` | `Codegen::TypeMaps::Postgresql` | Maps PostgreSQL data types (`int4`, `text`, `bool`, `timestamptz`, ...) to `HakumiType`. |
| `codegen/type_maps/mysql.rb` | `Codegen::TypeMaps::Mysql` | Maps MySQL data types (`int`, `varchar`, `tinyint`, `datetime`, ...) to `HakumiType`. |
| `codegen/type_maps/sqlite.rb` | `Codegen::TypeMaps::Sqlite` | Maps SQLite data types (`INTEGER`, `TEXT`, `REAL`, ...) to `HakumiType`. |
| `codegen/schema_reader.rb` | `Codegen::SchemaReader` | Reads `information_schema` to extract tables, columns (with type, nullability, defaults), primary keys, and foreign keys. Defines `ColumnInfo`, `ForeignKeyInfo`, and `TableInfo` structs. |
| `codegen/generator.rb` | `Codegen::Generator` | Generates `typed: strict` Ruby files from ERB templates. Uses folder-per-table structure: `checkable.rb` (field interface), `schema.rb` (field constants), `record.rb` (persisted record with `find`, `find_by`, `exists?`, `build`, `update!`, `delete!`, `reload!`, `to_h`), `new_record.rb` (pre-persist with validate!), `validated_record.rb` (validated with save!), `base_contract.rb` (overridable validation hooks: `on_all`, `on_create`, `on_update`, `on_persist`), `relation.rb` (typed Relation subclass), plus a manifest. Generates `has_many`/`belongs_to` associations with preload support from foreign keys. Auto-detects `created_at`/`updated_at` timestamp columns and sets `Time.now` on insert/update. Reads `output_dir`, `models_dir`, `contracts_dir`, `module_name` from global config. |
| `codegen/generator_validation.rb` | `Codegen::Generator` (reopened) | Validation, persistence, and variant builder methods extracted from Generator to stay under the ClassLength limit: `build_checkable`, `build_validated_record`, `build_base_contract`, `build_contract`, `build_variant_base`, `build_update_locals`, `build_delete_locals`, `build_update_sql`, `build_update_bind_list`, `timestamp_auto_column?`, `to_h_value_type`, `generate_contracts!`. |
