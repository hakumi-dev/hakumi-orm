<p align="center">
  <br />
  <img src=".github/logo.png" alt="Hakumi Logo" width="250" />
  <br />
</p>

<h1 align="center">Hakumi ORM</h1>

<p align="center">
  Statically-typed, high-performance ORM engine for Ruby
  <br />
  <a href="https://github.com/hakumi-dev/hakumi-orm"><strong>Source Code</strong></a>
  &middot;
  <a href="https://github.com/hakumi-dev/hakumi-orm/issues">Report Bug</a>
  &middot;
  <a href="https://github.com/hakumi-dev/hakumi-orm/blob/main/CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <a href="https://github.com/hakumi-dev/hakumi-orm/blob/main/LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <a href="https://ruby-doc.org/"><img src="https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg?logo=ruby" alt="Ruby >= 3.2" /></a>
</p>

---

## Table of Contents

| | |
|---|---|
| [About](#about) | Design principles and overview |
| [Quick Look](#quick-look) | Code sample at a glance |
| [How It Compares to ActiveRecord](#how-it-compares-to-activerecord) | Side-by-side comparison |
| [Installation](#installation) | Gem setup and requirements |
| [Configuration](#configuration) | Database connections, paths, options |
| [Code Generation](#code-generation) | Generate models from live schema |
| [Custom Models](#custom-models) | Your editable model layer |
| [Querying](#querying) | Relations, field predicates, expressions, joins |
| [CRUD Operations](#crud-operations) | Create, read, update, delete |
| [Associations](#associations) | has_many, has_one, belongs_to, through, preloading |
| [Contracts and Lifecycle Hooks](#contracts-and-lifecycle-hooks) | Validation, before/after hooks |
| [Record Variants](#record-variants) | Typed state narrowing for nullable columns |
| [Transactions](#transactions) | Savepoints, after_commit/after_rollback hooks |
| [Optimistic Locking](#optimistic-locking) | lock_version and StaleObjectError |
| [Soft Delete](#soft-delete) | Logical deletion with scopes |
| [Automatic Timestamps](#automatic-timestamps) | created_at / updated_at auto-set |
| [Data Types](#data-types) | Enums, JSON/JSONB, UUID, arrays, custom types |
| [Migrations](#migrations) | Dialect-aware DSL, DDL transactions, advisory locks |
| [Schema Drift Detection](#schema-drift-and-pending-migration-detection) | Fingerprint checks and pending migration guards |
| [Connection Pooling](#connection-pooling) | Thread-safe pool for multi-threaded apps |
| [Multi-Database Support](#multi-database-support) | Named databases, replicas, block switching |
| [Query Logging](#query-logging) | SQL logging with bind params and timing |
| [Rake Tasks](#rake-tasks) | All available rake commands |
| [Low-Level Reference](#low-level-reference) | Type casting, CompiledQuery |
| [Architecture](#architecture) | Source tree and module layout |
| [Development](#development) | Setup, CI, testing |

---

## About

HakumiORM generates fully typed models, query builders, and hydration code directly from your database schema. Every generated file is Sorbet "typed: strict" with **zero** "T.untyped", "T.unsafe", or "T.must" in the output.

No "method_missing". No "define_method". No runtime reflection for column access.

### Design Principles

- **100% statically typed** -- Sorbet "typed: strict" across the entire codebase
- **Codegen over convention** -- models are generated from your schema, not inferred at runtime
- **Minimal allocations** -- designed for low GC pressure and YJIT-friendly object layouts
- **Prepared statements only** -- all values go through bind parameters, never interpolated into SQL
- **No Arel dependency** -- SQL is built directly from a typed expression tree with sequential bind markers
- **Type-state validation** -- "Record::New" -> "Record::Validated" -> "Record" lifecycle enforced at compile time
- **Pre-persist vs persisted types** -- "UserRecord::New" (without "id") and "UserRecord" (with "id") are distinct types
- **Multi-database support** -- dialect abstraction for PostgreSQL, MySQL, and SQLite; named databases with "HakumiORM.using(:replica)" block switching

## Quick Look

```ruby
active_users = User
  .where(UserSchema::ACTIVE.eq(true))
  .where(UserSchema::AGE.gt(18))
  .order(UserSchema::NAME.asc)
  .limit(25)
  .offset(50)
  .to_a
```

Every field constant knows its type at compile time. "IntField" exposes "gt", "lt", "between" but not "like". "StrField" exposes "like", "ilike" but not "gt". "BoolField" exposes neither. Sorbet catches type mismatches **before runtime**:

```ruby
UserSchema::AGE.like("%foo")    # Sorbet error: method 'like' does not exist on IntField
UserSchema::EMAIL.gt(5)         # Sorbet error: expected String, got Integer
UserSchema::ACTIVE.between(1,2) # Sorbet error: method 'between' does not exist on BoolField
```

## How It Compares to ActiveRecord

### Model definition

In ActiveRecord, a model is a single class that infers everything from the database at runtime:

```ruby
# ActiveRecord -- app/models/user.rb
class User < ApplicationRecord
  has_many :posts
end

User.columns  # discovered at runtime via method_missing
```

In HakumiORM, every model is generated from the schema as typed, explicit code:

```
db/schema/                 <-- always overwritten by codegen
  user/
    checkable.rb           # UserRecord::Checkable -- interface for validatable fields
    schema.rb              # UserSchema -- typed Field constants
    record.rb              # UserRecord -- persisted record (all columns, keyword init)
    new_record.rb          # UserRecord::New -- pre-persist record (validate!)
    validated_record.rb    # UserRecord::Validated -- validated record (save!)
    base_contract.rb       # UserRecord::BaseContract -- overridable validation hooks
    variant_base.rb        # UserRecord::VariantBase -- delegation base for user-defined variants
    relation.rb            # UserRelation -- typed query builder
  manifest.rb              # require_relative for all files

app/models/                <-- generated once, never overwritten; yours to edit
  user.rb                  # class User < UserRecord
  post.rb                  # class Post < PostRecord

app/contracts/             <-- generated once, never overwritten
  user_contract.rb         # UserRecord::Contract < UserRecord::BaseContract
  post_contract.rb         # PostRecord::Contract < PostRecord::BaseContract
```

If you set `module_name` (for example `"App"` or `"App::Core"`), generated Ruby code is wrapped in that module and stub paths in `models_dir` / `contracts_dir` are nested to match it (for example `app/models/app/user.rb`, `app/contracts/app/user_contract.rb`).

### Querying

```ruby
# ActiveRecord
User.where(active: true).where("age > ?", 18).order(:name).limit(10)
User.where("email LIKE ?", "%@gmail.com")  # raw SQL strings, no type checking

# HakumiORM
User
  .where(UserSchema::ACTIVE.eq(true))
  .where(UserSchema::AGE.gt(18))
  .order(UserSchema::NAME.asc)
  .limit(10)

User.where(UserSchema::EMAIL.like("%@gmail.com"))
```

Key differences:

- AR uses hash conditions and raw SQL strings -- typos and type mismatches are caught at runtime (or not at all)
- HakumiORM uses typed "Field" objects -- Sorbet catches column name typos, wrong value types, and invalid operations at compile time

### Creating records

```ruby
# ActiveRecord
user = User.new(name: "Alice", email: "alice@example.com")
user.id    # => nil (before save)
user.save! # => true
user.id    # => 1 (after save)
# The same object changes state. "id" is T.nilable(Integer) everywhere.

# HakumiORM -- type-state enforced lifecycle
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
# new_user is UserRecord::New -- no "id" attribute at all

validated = new_user.validate!
# validated is UserRecord::Validated -- contract passed, New is immutable

user = validated.save!
# user is UserRecord -- "id" is Integer, guaranteed non-nil
user.id    # => 1 (always present, never nil)
```

The type system enforces the lifecycle: "New" -> "Validated" -> "Record". You **cannot** call "save!" on a "New" (must validate first), and you **cannot** get a "nil" id after persistence.

### Associations

```ruby
# ActiveRecord
class User < ApplicationRecord
  has_many :posts
end
user.posts  # => lazy ActiveRecord::Relation

# HakumiORM -- generated from foreign keys, fully typed
alice = User.find(1)
alice.posts              # => PostRelation (lazy, chainable)
alice.posts.to_a         # => T::Array[PostRecord]
alice.posts.where(PostSchema::PUBLISHED.eq(true)).count  # => Integer

post = Post.find(1)
post.user                # => T.nilable(UserRecord)
```

Associations are generated automatically from foreign keys. "has_many" returns a typed "Relation", "has_one" returns "T.nilable(Record)" (detected via UNIQUE constraints), "belongs_to" returns the related record. "has_many :through" is generated for FK chains and join tables using subqueries.

### Full comparison table

| | ActiveRecord | HakumiORM |
|---|---|---|
| Typing | Runtime, mostly untyped | "typed: strict", Sorbet-verified |
| Column access | "method_missing" / dynamic | Generated "attr_reader" with "sig" |
| Column names | Strings/symbols, checked at runtime | "Schema::FIELD" constants, checked at compile time |
| Query DSL | Strings / hash conditions | "Field[T]" objects with type-safe operations |
| Raw SQL escape | "where("sql ?", val)" | "where_raw("sql ?", [bind])" with typed binds |
| Subqueries | ".where(id: Sub.select(:id))" | "SubqueryExpr.new(field, :in, compiled)" |
| DISTINCT | ".distinct" | ".distinct" |
| GROUP BY / HAVING | ".group(:col).having("...")" | ".group(Field).having(Expr)" |
| Aggregates | ".sum", ".average", ".minimum", ".maximum" | ".sum(field)", ".average(field)", ".minimum(field)", ".maximum(field)" |
| Optimistic locking | "lock_version" column | "lock_version" column + "StaleObjectError" |
| Pessimistic locking | ".lock" / "FOR UPDATE" | ".lock" / ".lock("FOR SHARE")" |
| Multi-column pluck | ".pluck(:a, :b)" | ".pluck(FieldA, FieldB)" returns raw string arrays |
| SQL generation | Arel (dynamic AST) | "SqlCompiler" with sequential bind markers |
| Hydration | Reflection + type coercion | Generated positional "fetch_value" |
| New vs persisted | Same class, "id" is nilable | Type-state: "Record::New" -> "Record::Validated" -> "Record" |
| "has_many" | "has_many :posts" (DSL) | Generated from FK (returns typed Relation) |
| "has_one" | "has_one :profile" (DSL) | Generated when FK has UNIQUE constraint |
| "has_many :through" | "has_many :tags, through: :taggings" | Generated from FK chains and join tables (subquery) |
| "belongs_to" | "belongs_to :user" (DSL) | Generated from FK |
| Eager loading | "includes" / "preload" / "eager_load" | ".preload(:assoc)" with nested: ".preload(posts: :comments)" |
| Custom associations | Manual "has_many" with lambda/scope | Declarative via config, fully generated and preloadable |
| Dependent destroy | "dependent: :destroy" | "delete!(dependent: :destroy)" or ":delete_all" |
| Single-record update | "user.update!(name: "Bob")" | "user.update!(name: "Bob")" -- typed kwargs, validated |
| Single-record delete | "user.destroy!" | "user.delete!" |
| Callbacks | Before/after hooks | Contract hooks: "on_all", "on_create", "on_update", "on_persist", "on_destroy", "after_create", "after_update", "after_destroy" |
| Connection pool | Built-in pool | "ConnectionPool" (thread-safe, reentrant, configurable) |
| Transactions | "transaction { }" + nested | "transaction(requires_new: true)" + savepoints |
| JSON/JSONB | Automatic hash/array | "HakumiORM::Json" opaque wrapper with typed extractors |
| UUID | String column | "HakumiType::Uuid", "StrField", LIKE/ILIKE support |
| Array columns | "serialize :tags, Array" | "IntArrayField", "StrArrayField", PG array literal format |
| Custom types | "attribute :price, :money" | "TypeRegistry.register" with cast, field, and bind |
| Rake task | "rails db:migrate" etc. | "rake db:generate" |
| Dirty tracking | Automatic (mutable) | "diff(other)" / "changed_from?(other)" (immutable snapshots) |
| Timestamps | Automatic "created_at"/"updated_at" | Configurable via "created_at_column" / "updated_at_column" |
| Migrations | Built-in | Built-in: dialect-aware DSL, timestamped files, advisory locks |

## Installation

Add to your application's Gemfile:

```ruby
gem "hakumi_orm"
```

Then run:

```bash
bundle install
```

### Requirements

- Ruby >= 3.2
- Sorbet runtime ("sorbet-runtime" gem, pulled automatically)
- A database driver ("pg", "mysql2", or "sqlite3") depending on your target

## Configuration

Configure HakumiORM once at boot. The adapter connects automatically when first needed.

**PostgreSQL with user and password (typical development):**

```ruby
HakumiORM.configure do |config|
  config.adapter_name = :postgresql
  config.database     = "myapp_dev"
  config.host         = "localhost"
  config.port         = 5432
  config.username     = "postgres"
  config.password     = "postgres"
end
```

**MySQL with user and password:**

```ruby
HakumiORM.configure do |config|
  config.adapter_name = :mysql
  config.database     = "myapp_dev"
  config.host         = "localhost"
  config.port         = 3306
  config.username     = "root"
  config.password     = "root"
end
```

**SQLite (no credentials needed):**

```ruby
HakumiORM.configure do |config|
  config.adapter_name = :sqlite
  config.database     = "db/myapp.sqlite3"
end
```

**Connection URL (common in production / PaaS):**

```ruby
HakumiORM.configure do |config|
  config.database_url = ENV.fetch("DATABASE_URL")
end
```

Supported URL schemes: "postgresql://", "postgres://", "mysql2://", "mysql://", "sqlite3://", "sqlite://".

URL examples:

```
postgresql://user:password@host:5432/myapp
mysql2://root:secret@localhost:3306/myapp
sqlite3:///path/to/db.sqlite3
postgresql://user:p%40ssword@host/db?sslmode=require
```

Passwords with special characters ("@", "#", etc.) must be percent-encoded in URLs.

Query parameters ("sslmode", "connect_timeout", etc.) are passed directly to the database driver.

**SSL-encrypted connection:**

```ruby
HakumiORM.configure do |config|
  config.database_url = "postgresql://user:pass@host/db?sslmode=verify-full&sslrootcert=/path/to/ca.pem"
end
```

**Individual env vars (production without URL):**

```ruby
HakumiORM.configure do |config|
  config.adapter_name = :postgresql
  config.database = ENV.fetch("DB_NAME")
  config.host     = ENV.fetch("DB_HOST")
  config.port     = ENV.fetch("DB_PORT", "5432").to_i
  config.username = ENV.fetch("DB_USER")
  config.password = ENV.fetch("DB_PASSWORD")
end
```

**Peer / socket auth (no password):**

```ruby
HakumiORM.configure do |config|
  config.adapter_name = :postgresql
  config.database = "myapp_dev"
end
```

**Explicit adapter (advanced):**

```ruby
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::Postgresql.connect(dbname: "myapp")
end
```

**Paths and codegen options:**

```ruby
HakumiORM.configure do |config|
  config.output_dir    = "db/schema"
  config.models_dir    = "app/models"
  config.contracts_dir = "app/contracts"
  config.module_name   = "App"
  config.definitions_path = "db/definitions.rb"
end
```

| Option | Default | Description |
|---|---|---|
| "database_url" | -- | Connection URL. Parses scheme, credentials, host, port, database, and query params. |
| "adapter_name" | ":postgresql" | ":postgresql", ":mysql", or ":sqlite". Set automatically by "database_url". |
| "database" | "nil" | Database name. Set automatically by "database_url". |
| "host" | "nil" | Database host. "nil" uses local socket / localhost. |
| "port" | "nil" | Database port. "nil" uses default (5432 PG, 3306 MySQL). |
| "username" | "nil" | Database user. "nil" uses current system user. |
| "password" | "nil" | Database password. "nil" for peer / socket auth. |
| "connection_options" | "{}" | Extra driver params (sslmode, connect_timeout, etc.). Set automatically from URL query params. |
| "adapter" | auto | Set directly to skip lazy building. Takes precedence over connection params. |
| "log_level" | -- | Symbol (":debug", ":info", ":warn", ":error", ":fatal"). Creates an internal logger to "$stdout". |
| "logger" | "nil" | Any "HakumiORM::Loggable" implementor ("::Logger", Rails.logger, custom). "nil" = no logging, zero overhead. |
| "pretty_sql_logs" | "false" | Pretty SQL formatter (keywords + optional color). |
| "colorize_sql_logs" | "true" | ANSI colors when pretty logging is enabled. |
| "log_filter_parameters" | "["passw", "email", ...]" | Case-insensitive substrings used to mask sensitive bind values in logs. |
| "log_filter_mask" | ""[FILTERED]"" | Replacement text used for masked bind values. |
| "output_dir" | ""db/schema"" | Directory for generated schemas, records, and relations. |
| "models_dir" | "nil" | Directory for model stubs. "nil" = skip. |
| "contracts_dir" | "nil" | Directory for contract stubs. "nil" = skip. |
| "module_name" | "nil" | Namespace wrapping for generated code. |
| "form_model_adapter" | "HakumiORM::FormModel::NoopAdapter" | Adapter object for form integration. Must implement "HakumiORM::FormModelAdapter". Rails sets "HakumiORM::Framework::Rails::FormModel" by default. |
| "migrations_path" | ""db/migrate"" | Directory for migration files. |
| "definitions_path" | ""db/definitions.rb"" | Ruby file (or directory) loaded before codegen for custom associations and user-defined enums. |
| "seeds_path" | ""db/seeds.rb"" | Seed file executed by "rake db:seed". |

All generated methods ("find", "where", "save!", associations, etc.) default to "HakumiORM.adapter", so you never pass the adapter manually.

Generated records include "HakumiORM::FormModel::Default", so "to_model", "model_name", "to_key", and "errors" are available for form builders out of the box.

## Code Generation

Generate model files from your live database schema:

```ruby
reader = HakumiORM::Codegen::SchemaReader.new(HakumiORM.adapter)
tables = reader.read_tables

generator = HakumiORM::Codegen::Generator.new(tables)
generator.generate!
```

The generator reads "output_dir", "models_dir", and "module_name" from the global config. You can override per-call via "GeneratorOptions":

```ruby
opts = HakumiORM::Codegen::GeneratorOptions.new(
  dialect:           custom_dialect,
  output_dir:        "custom/path",
  models_dir:        "custom/models",
  module_name:       "MyApp",
  soft_delete_tables: { "articles" => "deleted_at", "posts" => "removed_at" },
  created_at_column: "created_at",            # auto-set on INSERT (nil to disable)
  updated_at_column: "updated_at"             # auto-set on INSERT and UPDATE (nil to disable)
)
generator = HakumiORM::Codegen::Generator.new(tables, opts)
```

### When to Regenerate

| Action | Requires regeneration? |
|---|---|
| Run a migration (add/remove column, table, FK) | Yes (automatic if using "db:migrate") |
| Add/change a custom association or enum in "db/definitions.rb" | Yes |
| Add a scope to a Relation | No |
| Edit a Contract hook | No |
| Override "custom_preload" (escape hatch) | No |
| Change "GeneratorOptions" (soft delete, timestamps) | Yes |

Regeneration also updates model annotations ("# == Schema Information ==" block) with the latest schema and associations.
When a model file has a module wrapper, the annotation block is inserted above the `module` line (not between `module` and `class`).

## Custom Models

Generated code lives in "db/schema/" and is always overwritten. Your models live in "app/models/" and are never touched after the initial stub generation:

```ruby
class User < UserRecord
  extend T::Sig

  sig { returns(String) }
  def display_name
    "#{name} <#{email}>"
  end

  sig { returns(PostRelation) }
  def published_posts
    posts.where(PostSchema::PUBLISHED.eq(true))
  end
end
```

The "models/" files are your public API. They inherit from the generated records and are where you add custom logic. You interact with "User", not "UserRecord":

```ruby
user = User.find(1)
user.published_posts.to_a
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.validate!.save!
```

## Querying

### Relations

"Relation" is a chainable, lazy query builder. Nothing hits the database until a terminal method ("to_a", "first", "count", etc.) is called.

#### Record Class Methods

These methods are generated on every record class (e.g., "UserRecord", and inherited by "User").

| Method | Returns | Description |
|---|---|---|
| "find(pk)" | "T.nilable(Record)" | Find by primary key. Returns "nil" if not found. |
| "find_by(expr)" | "T.nilable(Record)" | First record matching an expression. Sugar for ".where(expr).first". |
| "exists?(expr)" | "T::Boolean" | "SELECT 1 ... LIMIT 1" -- checks if any row matches. |
| "where(expr)" | "Relation" | Start a filtered query. Returns a chainable "Relation". |
| "all" | "Relation" | Return a "Relation" for all rows in the table. |
| "build(...)" | "Record::New" | Create a new unpersisted record with keyword arguments. |

```ruby
user = User.find(42)
user = User.find_by(UserSchema::EMAIL.eq("alice@example.com"))
User.exists?(UserSchema::EMAIL.eq("alice@example.com"))
```

#### Chainable Methods (return "self")

| Method | Description |
|---|---|
| "where(expr)" | Add a WHERE condition. Multiple calls are ANDed. |
| "where_raw(sql, binds)" | Add a raw SQL WHERE fragment with "?" bind placeholders. |
| "where_not(expr)" | Add a negated WHERE condition. |
| "or(relation)" | Combine with another relation via OR. |
| "order(clause)" | Add ORDER BY via an "OrderClause" (e.g., "UserSchema::NAME.asc"). |
| "order_by(field, direction)" | Add ORDER BY via field + ":asc" / ":desc" symbol. |
| "limit(n)" | Set LIMIT. |
| "offset(n)" | Set OFFSET. |
| "distinct" | Add "SELECT DISTINCT". |
| "group(*fields)" | Add "GROUP BY" clause. |
| "having(expr)" | Add "HAVING" clause (used with "group"). |
| "lock(clause)" | Append locking clause (default: "FOR UPDATE"). |
| "join(clause)" | Add a JOIN clause. |
| "preload(*names)" | Eager-load associations after the main query (avoids N+1). |

```ruby
User
  .where(UserSchema::ACTIVE.eq(true))
  .order(UserSchema::NAME.asc)
  .distinct
  .limit(25)
  .offset(50)
```

#### Terminal Methods (execute the query)

| Method | Returns | Description |
|---|---|---|
| "to_a" | "T::Array[Record]" | Execute and return all matching records. |
| "first" | "T.nilable(Record)" | Execute with LIMIT 1 and return the first record. |
| "count" | "Integer" | Execute "SELECT COUNT(*)" and return the count. |
| "exists?" | "T::Boolean" | Execute "SELECT 1 ... LIMIT 1" and return whether any row matches. |
| "pluck_raw(field)" | "T::Array[T.nilable(String)]" | Return raw string values for a single column. |
| "pluck(*fields)" | "T::Array[T::Array[T.nilable(String)]]" | Multi-column pluck returning raw string arrays. |
| "delete_all" | "Integer" | Execute "DELETE" and return the number of deleted rows. |
| "update_all(assignments)" | "Integer" | Execute "UPDATE" and return the number of updated rows. |
| "sum(field)" | "T.nilable(String)" | Execute "SELECT SUM(field)". |
| "average(field)" | "T.nilable(String)" | Execute "SELECT AVG(field)". |
| "minimum(field)" | "T.nilable(String)" | Execute "SELECT MIN(field)". |
| "maximum(field)" | "T.nilable(String)" | Execute "SELECT MAX(field)". |
| "to_sql" | "CompiledQuery" | Return the compiled SQL + binds **without executing**. |

```ruby
users = User.all.to_a
first = User.all.order(UserSchema::NAME.asc).first

total = User.where(UserSchema::ACTIVE.eq(true)).count
total_age = User.all.sum(UserSchema::AGE)

pairs = User.all.pluck(UserSchema::NAME, UserSchema::EMAIL)
# => [["Alice", "a@b.com"], ["Bob", "b@c.com"]]

names = User.all.order(UserSchema::NAME.asc).pluck_raw(UserSchema::NAME)
# => ["Alice", "Bob", "Carol"]

compiled = User.where(UserSchema::AGE.gt(18)).to_sql
compiled.sql     # => 'SELECT ... WHERE "users"."age" > $1'
compiled.binds   # => [#<IntBind value=18>]

User.where(UserSchema::ACTIVE.eq(false))
  .update_all([HakumiORM::Assignment.new(UserSchema::ACTIVE, HakumiORM::BoolBind.new(true))])

User.where(UserSchema::NAME.eq("temp")).delete_all
```

### Field Predicates

Every "Schema::FIELD" constant is a typed field object. The available predicates depend on the field type.

#### All fields ("Field")

| Method | SQL | Example |
|---|---|---|
| "eq(value)" | "= $1" | "UserSchema::NAME.eq("Alice")" |
| "neq(value)" | "<> $1" | "UserSchema::NAME.neq("Alice")" |
| "in_list(values)" | "IN ($1, $2, ...)" | "UserSchema::ID.in_list([1, 2, 3])" |
| "not_in_list(values)" | "NOT IN ($1, $2, ...)" | "UserSchema::ID.not_in_list([1, 2])" |
| "is_null" | "IS NULL" | "UserSchema::AGE.is_null" |
| "is_not_null" | "IS NOT NULL" | "UserSchema::AGE.is_not_null" |

#### Comparable fields ("IntField", "FloatField", "DecimalField", "TimeField", "DateField")

| Method | SQL | Example |
|---|---|---|
| "gt(value)" | "> $1" | "UserSchema::AGE.gt(18)" |
| "gte(value)" | ">= $1" | "UserSchema::AGE.gte(18)" |
| "lt(value)" | "< $1" | "UserSchema::AGE.lt(65)" |
| "lte(value)" | "<= $1" | "UserSchema::AGE.lte(65)" |
| "between(low, high)" | "BETWEEN $1 AND $2" | "UserSchema::AGE.between(18, 65)" |

#### Text fields ("StrField")

| Method | SQL | Example |
|---|---|---|
| "like(pattern)" | "LIKE $1" | "UserSchema::EMAIL.like("%@gmail.com")" |
| "ilike(pattern)" | "ILIKE $1" | "UserSchema::NAME.ilike("alice")" |

#### Ordering

| Method | Returns | Example |
|---|---|---|
| "asc" | "OrderClause" | "UserSchema::NAME.asc" |
| "desc" | "OrderClause" | "UserSchema::NAME.desc" |

### Expression Combinators

Predicates return "Expr" objects that can be combined with boolean logic:

| Method | SQL | Example |
|---|---|---|
| "expr.and(other)" | "(left) AND (right)" | "UserSchema::ACTIVE.eq(true).and(UserSchema::AGE.gt(18))" |
| "expr.or(other)" | "(left) OR (right)" | "UserSchema::NAME.eq("Alice").or(UserSchema::NAME.eq("Bob"))" |
| "expr.not" | "NOT (expr)" | "UserSchema::ACTIVE.eq(true).not" |

Multiple ".where" calls are ANDed automatically:

```ruby
# These are equivalent
User.where(UserSchema::AGE.gte(18)).where(UserSchema::ACTIVE.eq(true))
User.where(UserSchema::AGE.gte(18).and(UserSchema::ACTIVE.eq(true)))
```

Expressions nest with deterministic parentheses:

```ruby
User.where(
  UserSchema::AGE.gte(18)
    .and(UserSchema::EMAIL.like("%@company.com"))
    .or(UserSchema::NAME.eq("admin"))
)
```

#### Raw SQL Expressions

For SQL that can't be expressed with typed fields, use "RawExpr":

```ruby
raw = HakumiORM::RawExpr.new("LENGTH(\"users\".\"name\") > ?", [HakumiORM::IntBind.new(5)])
User.where(raw).to_a
```

"?" placeholders are replaced with dialect-specific bind markers ("$1", "$2", ...). "RawExpr" can be combined with other expressions via ".and" / ".or".

#### Subquery Expressions

Use "SubqueryExpr" to embed a compiled SELECT as a subquery in WHERE:

```ruby
sub = compiler.select(table: "orders", columns: [OrderSchema::USER_ID])
expr = HakumiORM::SubqueryExpr.new(UserSchema::ID, :in, sub)
User.where(expr).to_a
# => SELECT ... WHERE "users"."id" IN (SELECT ...)
```

Supported operators: ":in", ":not_in". Bind markers are automatically rebased to avoid collisions.

#### Operator Aliases

All predicates and combinators have operator aliases that delegate to the named methods:

| Operator | Delegates to | Available on |
|---|---|---|
| "==" | "eq" | All fields |
| "!=" | "neq" | All fields |
| ">", ">=", "<", "<=" | "gt", "gte", "lt", "lte" | "ComparableField" only |
| "&" | "and" | "Expr" |
| "\|" | "or" | "Expr" |
| "!" | "not" | "Expr" |

> **Note:** "=="/"!=" return "Predicate", not "Boolean". Ruby's "&&"/"||" cannot be overloaded, so use "&"/"|" instead. Because "&"/"|" have higher precedence than comparison operators, parentheses are required: "(AGE > 18) & (ACTIVE == true)".

### Joins

Use "join" to filter records based on related table conditions. The join is for filtering only -- the SELECT returns the main table's columns.

```ruby
join = HakumiORM::JoinClause.new(:inner, "posts", UserSchema::ID, PostSchema::USER_ID)
users = User.all
  .join(join)
  .where(PostSchema::PUBLISHED.eq(true))
  .order(UserSchema::NAME.asc)
  .to_a
```

Supported join types: ":inner", ":left", ":right", ":cross".

## CRUD Operations

### Creating Records

```ruby
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.name    # => "Alice"
new_user.class   # => UserRecord::New (no id attribute)

validated = new_user.validate!
validated.class  # => UserRecord::Validated (immutable)

user = validated.save!
user.class       # => UserRecord
user.id          # => Integer (guaranteed non-nil)
```

The type-state lifecycle:

| Method | Transition | Description |
|---|---|---|
| "build(...)" | -- -> "Record::New" | Create an unpersisted record with keyword arguments. |
| "validate!" | "New" -> "Validated" | Run "Contract.on_all" + "Contract.on_create". Raises "ValidationError" on failure. |
| "save!" | "Validated" -> "Record" | Run "Contract.on_persist", then "INSERT ... RETURNING *". Returns a hydrated "Record" with "id". |

If the table has "created_at" / "updated_at" timestamp columns, they are automatically set to "Time.now".

### Updating Records

```ruby
updated = user.update!(name: "Bob", active: false)
updated.name     # => "Bob"
updated.active   # => false
updated.email    # => unchanged from original
```

Takes keyword arguments for each column (defaults to current values for unchanged fields). Validates via "Contract.on_all", "Contract.on_update", and "Contract.on_persist", then executes "UPDATE ... RETURNING *". Returns a new hydrated "Record".

If the table has an "updated_at" timestamp column, it is automatically set to "Time.now" on every "update!" call.

#### Additional instance methods

| Method | Returns | Description |
|---|---|---|
| "reload!" | "Record" | Re-fetch from the database by primary key. |
| "to_h" | "Hash" | Convert to a hash keyed by column name (no "T.untyped"). |
| "as_json" | "Hash" | JSON-serializable hash with string keys. Supports "only:" and "except:". |
| "diff(other)" | "Hash" | Compare two records and return changed fields as "{ field: [new, old] }". |
| "changed_from?(other)" | "T::Boolean" | Whether any column differs from another record. |

### Deleting Records

```ruby
user.delete!             # => void (raises if record doesn't exist)

User.where(UserSchema::ACTIVE.eq(false)).delete_all  # => Integer (rows deleted)
```

## Associations

Associations are generated automatically from foreign keys. No manual declaration needed.

### "has_many" (one-to-many)

Returns a **lazy "Relation"** -- no query is executed until a terminal method is called. The relation is fully chainable.

```ruby
alice = User.find(1)

alice.posts                  # => PostRelation (no query yet)
alice.posts.to_a             # => T::Array[PostRecord] (executes SELECT)
alice.posts.count            # => Integer (executes SELECT COUNT(*))

alice.posts
  .where(PostSchema::PUBLISHED.eq(true))
  .order(PostSchema::TITLE.asc)
  .to_a
```

### "has_one" (one-to-one)

Generated when the FK column on the child table has a UNIQUE constraint. Returns "T.nilable(Record)".

```ruby
alice = User.find(1)
alice.profile                # => T.nilable(ProfileRecord) (executes SELECT ... LIMIT 1)
```

### "belongs_to" (many-to-one)

Returns the related record by executing a "find" on the foreign key value.

```ruby
post = Post.find(1)
post.user                    # => T.nilable(UserRecord) (executes SELECT)
```

### "has_many :through" (transitive associations)

Generated automatically for FK chains and join tables. Uses "SubqueryExpr" internally.

```ruby
alice = User.find(1)
alice.roles                  # => RoleRelation (subquery: WHERE id IN (SELECT role_id FROM users_roles WHERE user_id = ?))
alice.roles.to_a             # => T::Array[RoleRecord]

alice.comments               # => CommentRelation (subquery through posts)
alice.comments.where(CommentSchema::APPROVED.eq(true)).to_a
```

### Preloading (eager loading)

Use "preload" to batch-load associations in a single extra query:

```ruby
users = User.all.preload(:posts).to_a

users.each do |u|
  puts u.posts.count             # no query -- data is already loaded
end
```

Nested preloads load associations recursively:

```ruby
users = User.all.preload(posts: :comments).to_a
User.all.preload(:profile, posts: [:comments, :tags]).to_a
```

"preload" works for "has_many", "has_one", and "belongs_to". A depth guard ("MAX_PRELOAD_DEPTH = 8") prevents runaway recursion if preload nodes are constructed manually with circular references.

### Custom Associations (non-FK based)

For associations based on a different column match (email, slug, external_id), declare them in "db/definitions.rb" and the generator produces everything -- lazy accessor, batch preload, cache, and dispatch:

```ruby
# db/definitions.rb
HakumiORM.associate("users") do |a|
  a.has_many "authored_articles", target: "articles", foreign_key: "author_email", primary_key: "email"
  a.has_one  "latest_comment",    target: "comments", foreign_key: "user_email",   primary_key: "email", order_by: "created_at"
end
```

The generator produces the same code as FK-based associations:

```ruby
alice = User.find(1)

alice.authored_articles        # Custom has_many (generated from config)
alice.latest_comment           # Custom has_one with ordering

alice.authored_articles.where(ArticleSchema::PUBLISHED.eq(true)).count

users = User.all.preload(:posts, :authored_articles, :latest_comment).to_a
```

Available methods inside the "associate" block:

| Method | Required fields | Description |
|---|---|---|
| "has_many" | "name", "target:", "foreign_key:", "primary_key:" | Returns a Relation (lazy, chainable). |
| "has_one" | "name", "target:", "foreign_key:", "primary_key:" | Returns "T.nilable(Record)". Optional "order_by:" for deterministic results (always DESC). |

The generator validates at codegen time: tables and columns must exist, source column must be NOT NULL, types must be compatible, names must not collide with existing associations or columns.

The definitions file/path is configurable:

```ruby
HakumiORM.configure do |c|
  c.definitions_path = "db/definitions.rb" # default
end
```

### Custom Associations (escape hatch)

For associations that cannot be expressed as a field match (multi-step subqueries, external APIs, composite keys, polymorphic patterns), override "custom_preload" in the Relation manually:

```ruby
class UserRelation
  extend T::Sig

  sig { override.params(name: Symbol, records: T::Array[UserRecord], adapter: ::HakumiORM::Adapter::Base).void }
  def custom_preload(name, records, adapter)
    case name
    when :recent_audits
      ids = records.map { |r| r.id.to_s }
      all = AuditRelation.new
        .where(AuditSchema::ENTITY_TYPE.eq("user"))
        .where(AuditSchema::ENTITY_ID.in_list(ids))
        .to_a(adapter: adapter)
      grouped = all.group_by(&:entity_id)
      records.each { |r| r.instance_variable_set(:@_recent_audits, grouped[r.id.to_s] || []) }
    end
  end
end
```

The generated "run_preloads" delegates any association name it does not recognize to "custom_preload", which is a no-op by default.

### Dependent delete/destroy

When deleting a parent record, you can cascade to associated records:

```ruby
user.delete!(dependent: :delete_all)   # batch SQL DELETE on children (no callbacks)
user.delete!(dependent: :destroy)      # loads children and calls delete! on each (cascades recursively)
user.delete!                           # :none (default) -- no cascade, relies on DB constraints
```

The "dependent" parameter is only generated when the record has "has_many" or "has_one" associations.

### Model Annotations

"db:generate" auto-updates a comment block at the top of each model file showing columns, types, and ALL associations (FK + custom + through). The user code below the annotation is never touched:

```ruby
# == Schema Information ==
#
# Table: users
# Primary key: id (bigint, not null)
#
# Columns:
#   active      boolean     not null, default: true
#   age         integer     nullable
#   email       string      not null
#   id          bigint      not null, PK
#   name        string      not null
#
# Associations:
#   has_many    :posts                (FK: posts.user_id -> users.id)
#   belongs_to  :company              (FK: users.company_id -> companies.id)
#   has_many    :authored_articles    (custom: articles.author_email -> users.email)
#   has_one     :latest_comment       (custom: comments.user_email -> users.email, order: created_at)
#   has_many    :roles                (through: users_roles)
#
# == End Schema Information ==

class User < UserRecord
  # your code, scopes, business logic
end
```

You can also list all associations from the command line:

```bash
bundle exec rake db:associations            # all models
bundle exec rake db:associations[users]     # single model
```

## Contracts and Lifecycle Hooks

Each model has a Contract that controls validation and post-write side effects. Contracts are generated once in "contracts_dir" and never overwritten.

Public validation API:

- "validates" for standard validators (presence, blank/absence, length, format, numericality, inclusion, exclusion, comparison)
- "validate" for custom validation methods

Post-write hooks:

- "after_create", "after_update", "after_destroy"

### Execution order per operation

**"validate!" (New -> Validated):**

```
1. run rules with "on: :all"
2. run rules with "on: :create"
3. raise ValidationError if errors       -- STOPS here on failure
4. return Validated
```

**"save!" (Validated -> Record, executes INSERT):**

```
1. run rules with "on: :all"
2. run rules with "on: :persist"
3. raise ValidationError if errors       -- STOPS here, no INSERT
4. INSERT ... RETURNING *                -- executes SQL
5. Contract.after_create(record, adapter) -- side effects (record is persisted)
6. return Record
```

**"update!" (Record -> Record, executes UPDATE):**

```
1. run rules with "on: :all"
2. run rules with "on: :update"
3. run rules with "on: :persist"
4. raise ValidationError if errors       -- STOPS here, no UPDATE
5. UPDATE ... RETURNING *                -- executes SQL
6. Contract.after_update(record, adapter) -- side effects (record is updated)
7. return Record
```

**"delete!" (Record -> void, executes DELETE or soft-delete UPDATE):**

```
1. run rules with "on: :destroy"
2. raise ValidationError if errors       -- STOPS here, no DELETE
3. DELETE FROM ... WHERE pk = $1         -- executes SQL
4. Contract.after_destroy(record, adapter) -- side effects (record is deleted)
```

### Contract example

```ruby
# app/contracts/user_contract.rb
class UserRecord::Contract < UserRecord::BaseContract
  extend T::Sig

  validates :name, presence: true
  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }
  validates :login_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, on: :create
  validate :email_not_reserved, on: :create

  sig { params(record: UserRecord::New, e: ::HakumiORM::Errors).void }
  def self.email_not_reserved(record, e)
    e.add(:email, "is reserved") if record.email.end_with?("@system.internal")
  end

  sig { override.params(record: UserRecord, adapter: ::HakumiORM::Adapter::Base).void }
  def self.after_create(record, adapter)
    AuditLog.record!("user_created", record.id, adapter: adapter)
  end
end
```

Custom validation methods receive "(record, errors)" and should add messages through "e.add(...)".

When any rule adds errors, a "ValidationError" is raised:

```ruby
begin
  new_user.validate!
rescue HakumiORM::ValidationError => e
  e.errors.messages  # => { name: ["cannot be blank"], email: ["must contain @"] }
  e.errors.count     # => 2
end
```

Validation contexts for "validates" and "validate":

- "on: :all" (default)
- "on: :create"
- "on: :update"
- "on: :persist"
- "on: :destroy"

Execution timing by operation:

- "validate!": runs ":all", then ":create"
- "save!": runs ":all", then ":persist", then INSERT; then "after_create"
- "update!": runs ":all", then ":update", then ":persist", then UPDATE; then "after_update"
- "delete!": runs ":destroy", then DELETE; then "after_destroy"

Important behavior:

- Any error added during validation stops the SQL write and raises "ValidationError".
- "after_*" hooks run only after successful SQL.

## Record Variants

In a typical ORM, every nullable column is "T.nilable(X)" everywhere. If your "performance_reviews" table has "score integer NULL", then "review.score" is always "T.nilable(Integer)" -- even when your business logic guarantees it's present for completed reviews.

Record Variants solve this with **real static typing** -- the variant constructor demands non-nil values via keyword arguments, and Sorbet verifies every call site at compile time. No runtime assertions disguised as type safety.

The codegen generates a "Record::VariantBase" that delegates all columns. You subclass it, add "attr_reader" for narrowed fields, and declare them as non-nil kwargs:

```ruby
# app/models/performance_review/completed.rb
class PerformanceReview::Completed < PerformanceReviewRecord::VariantBase
  extend T::Sig

  sig { returns(Integer) }
  attr_reader :score

  sig { returns(Time) }
  attr_reader :completed_at

  sig { params(record: PerformanceReviewRecord, score: Integer, completed_at: Time).void }
  def initialize(record:, score:, completed_at:)
    super(record: record)
    @score = T.let(score, Integer)
    @completed_at = T.let(completed_at, Time)
  end
end
```

The "as_*" methods use flow typing on local variables -- Sorbet verifies the narrowing:

```ruby
# app/models/performance_review.rb
class PerformanceReview < PerformanceReviewRecord
  extend T::Sig

  sig { returns(T.nilable(Completed)) }
  def as_completed
    s  = score
    ca = completed_at
    return nil unless s && ca

    Completed.new(record: self, score: s, completed_at: ca)
  end

  sig { returns(Completed) }
  def as_completed!
    as_completed || raise(HakumiORM::Error, "not a completed review")
  end
end
```

Variants can form a **progressive inheritance chain** that models domain progression:

```ruby
# Draft → base (no narrowing)
class PerformanceReview::Draft < PerformanceReviewRecord::VariantBase
end

# Started → narrows started_at
class PerformanceReview::Started < PerformanceReview::Draft
  sig { returns(Time) }
  attr_reader :started_at
  # ...
end

# Completed → inherits started_at from Started, narrows score + completed_at
class PerformanceReview::Completed < PerformanceReview::Started
  sig { returns(Integer) }
  attr_reader :score
  # ...
end
```

This also supports **branching** -- not just linear progression:

```
Draft
├── Started
│   ├── Completed
│   └── Cancelled
└── Rejected
```

Key points:

- **Real static typing** -- variant constructors demand non-nil kwargs; Sorbet verifies call sites at compile time
- **No "T.must"** -- "T.let" in constructors is a declaration, not a cast (types already match)
- **Progressive inheritance** -- variants chain ("Completed < Started < Draft"), narrowing accumulates
- **Branching** -- model tree-shaped domain logic, not just linear state machines
- **"VariantBase" is codegen** -- mechanical delegation of all columns, always regenerated, never edited

## Transactions

### Nested Transactions (Savepoints)

```ruby
adapter.transaction do |a|
  a.exec("INSERT INTO users ...")

  adapter.transaction(requires_new: true) do |inner|
    inner.exec("INSERT INTO posts ...")
    raise "oops"  # rolls back only the inner savepoint
  end

  # Outer transaction continues
end
```

Without "requires_new: true", nested calls are no-ops (reuse the outer transaction). With it, each level uses "SAVEPOINT hakumi_sp_N" / "RELEASE" / "ROLLBACK TO".

### Transaction Hooks

For side effects that must wait until the transaction commits (emails, background jobs, external APIs):

```ruby
adapter.transaction do |txn|
  user = validated.save!

  txn.after_commit { WelcomeMailer.deliver(user.email) }
  txn.after_rollback { ErrorTracker.log("user creation failed") }
end
```

- "after_commit" fires after COMMIT, not during the transaction
- "after_rollback" fires after ROLLBACK
- Callbacks registered inside a savepoint are **isolated**: if the savepoint is released, its "after_commit" callbacks propagate to the parent transaction; if the savepoint rolls back, its "after_commit" callbacks are **discarded** and its "after_rollback" callbacks fire immediately
- Multiple callbacks fire in registration order
- Zero overhead when not used -- no arrays allocated until "after_commit" is called

## Optimistic Locking

If a table has a "lock_version" integer column, the codegen automatically:

- Adds "lock_version = lock_version + 1" to every "UPDATE"
- Adds "WHERE lock_version = $current" to prevent stale writes
- Excludes "lock_version" from "update!" user parameters
- Raises "StaleObjectError" if the row was modified by another process

```ruby
user = User.find(1)

other = User.find(1)
other.update!(name: "Other")

user.update!(name: "Stale")  # => HakumiORM::StaleObjectError
```

## Soft Delete

Soft delete is disabled by default. To enable it, list the tables and their deletion marker column in "soft_delete_tables":

```ruby
opts = HakumiORM::Codegen::GeneratorOptions.new(
  soft_delete_tables: {
    "articles" => "deleted_at",
    "comments" => "removed_at",
  }
)
```

When enabled for a table:

- **delete!** executes UPDATE SET column = NOW() instead of DELETE
- **really_delete!** executes a hard DELETE FROM (bypasses soft delete)
- **deleted?** returns true when the column is non-nil
- **Default scope** filters out soft-deleted records (WHERE column IS NULL) on all queries
- **with_deleted** removes the default scope to include soft-deleted records
- **only_deleted** replaces the scope with WHERE column IS NOT NULL
- **unscoped** clears all default scopes (including soft delete)

```ruby
Article.all.to_a              # only non-deleted articles
Article.all.with_deleted.to_a # all articles, including deleted
Article.all.only_deleted.to_a # only deleted articles

article = Article.find(1)
article.deleted?              # => false
article.delete!               # UPDATE SET deleted_at = NOW()
article.really_delete!        # DELETE FROM articles WHERE id = 1
```

Each table can use a different column name -- there is no hardcoded default.

## Automatic Timestamps

If your table has timestamp columns matching "created_at_column" and/or "updated_at_column" (configurable in "GeneratorOptions"):

- **On "save!" (insert):** Both are set to "Time.now"
- **On "update!":** Only "updated_at_column" is set to "Time.now"

Defaults to ""created_at"" and ""updated_at"". Pass "nil" to disable either:

```ruby
opts = HakumiORM::Codegen::GeneratorOptions.new(
  created_at_column: "inserted_at",   # custom name
  updated_at_column: nil              # disable auto-update timestamp
)
```

## Data Types

### User-Defined Enums

For databases without native enum types (SQLite, MySQL), or when you want explicit control over enum values, declare enums in the same "db/definitions.rb" file:

```ruby
# db/definitions.rb
HakumiORM.define_enums("users") do |e|
  e.enum :role, { admin: 0, author: 1, reader: 2 }, prefix: :role
  e.enum :status, { active: 0, banned: 1 }, suffix: :status
end
```

Signature: `e.enum(column_name, values_hash, prefix: nil, suffix: nil)`

- **column_name** -- Symbol matching the integer column in the DB.
- **values_hash** -- `{ sym: int }` mapping. Positions are explicit and customizable.
- **prefix / suffix** -- Optional. Controls predicate method naming.

The generator produces "T::Enum" classes and predicate methods:

```ruby
user.role              # => UsersRoleEnum::ADMIN
user.role_admin?       # => true  (prefix: :role generates role_admin?, role_author?, ...)
user.active_status?    # => true  (suffix: :status generates active_status?, banned_status?)
```

The generator validates column compatibility at codegen time: user-defined enums require an integer column. PG native enums are auto-detected from the schema and do not need manual declaration.

### JSON/JSONB Columns

JSON and JSONB columns are automatically mapped to "HakumiORM::Json". The "Json" class stores the raw JSON string internally and provides typed accessors -- zero "Object", zero "T.untyped":

```ruby
event = Event.find(1)
event.payload            # => HakumiORM::Json

event.payload["key"]           # => T.nilable(Json)
event.payload["nested"]["deep"]  # => T.nilable(Json)
event.payload.at(0)            # => T.nilable(Json)

event.payload["name"]&.as_s   # => T.nilable(String)
event.payload["count"]&.as_i  # => T.nilable(Integer)
event.payload["rate"]&.as_f   # => T.nilable(Float)
event.payload["active"]&.as_bool  # => T.nilable(T::Boolean)

event.payload.to_json          # => String
event.payload.raw_json         # => String (same)

Event.build(
  name: "signup",
  payload: HakumiORM::Json.from_hash({ "source" => "web", "ip" => "1.2.3.4" })
)
```

"JsonField" supports "eq", "neq", "is_null", "is_not_null". For JSON path queries, use "where_raw".

### UUID Columns

UUID columns map to "String" / "StrField" with full LIKE/ILIKE support:

```ruby
token = Token.find(1)
token.token_id           # => String ("550e8400-e29b-41d4-a716-446655440000")

Token.where(TokenSchema::TOKEN_ID.eq("550e8400-..."))
```

### Array Columns

PostgreSQL array columns ("integer[]", "text[]", "float8[]", "bool[]") are automatically mapped:

```ruby
post = Post.find(1)
post.tag_ids         # => T::Array[T.nilable(Integer)]

Post.where(PostSchema::TAG_IDS.eq([1, 2, 3]))
Post.where(PostSchema::TAG_IDS.is_null)
```

Array values are serialized as PG array literals ("{1,2,3}") and parsed back with proper handling of NULLs, quoted strings, and commas inside values. Supported array predicates: "eq", "neq", "is_null", "is_not_null".

### Custom Types

Scaffold a custom type with the rake task:

```bash
bundle exec rake db:type[money]
```

This generates two files that you edit to fit your domain:

- "money_field.rb" -- Field subclass with "to_bind" returning an existing Bind
- "money_type.rb" -- TypeRegistry registration (ruby_type, cast, field_class)

A custom type has three pieces, each handling one direction of the data flow:

| Piece | Direction | When it runs | What it does |
|---|---|---|---|
| "Field.to_bind" | Ruby -> DB | Runtime (queries, inserts) | Converts your Ruby object to an existing Bind ("DecimalBind", "StrBind", etc.) |
| "cast_expression" | DB -> Ruby | **Codegen time** (not runtime) | Produces a line of Ruby code that the generator writes into the hydrator file |
| "TypeRegistry" | Wiring | Codegen time | Tells the generator which Field, Bind, and cast to use for a given column type |

#### Step 1: Define the Ruby type

```ruby
Money = Struct.new(:cents) do
  def to_d = BigDecimal(cents, 10) / 100
  def self.from_decimal(raw) = new((BigDecimal(raw) * 100).to_i)
end
```

#### Step 2: Create the Field (Ruby -> DB)

The Field converts your Ruby type to a Bind that the DB understands:

```ruby
class MoneyField < ::HakumiORM::Field
  extend T::Sig
  ValueType = type_member { { fixed: Money } }

  sig { override.params(value: Money).returns(::HakumiORM::Bind) }
  def to_bind(value)
    ::HakumiORM::DecimalBind.new(value.to_d)
  end
end
```

#### Step 3: Register for codegen (DB -> Ruby)

"cast_expression" is a lambda that produces Ruby source code. It runs once during "rake db:generate" and the string it returns is written directly into the generated file.

```ruby
HakumiORM::Codegen::TypeRegistry.register(
  name: :money,
  ruby_type: "Money",
  cast_expression: lambda { |raw_expr, nullable|
    nullable ? "((_hv = #{raw_expr}).nil? ? nil : Money.from_decimal(_hv))" : "Money.from_decimal(#{raw_expr})"
  },
  field_class: "::MoneyField",
  bind_class: "::HakumiORM::DecimalBind"
)

HakumiORM::Codegen::TypeRegistry.map_pg_type("money_col", :money)
```

#### Full round-trip

```ruby
product = Product.find(1)
product.price  # => Money -- hydrated by the generated code above

Product.where(ProductSchema::PRICE.eq(Money.new(9995)))
# MoneyField#to_bind returns DecimalBind(99.95)
# SQL: SELECT ... WHERE "products"."price" = $1   binds: ["99.95"]
```

Network types ("inet", "cidr", "macaddr") and "hstore" are mapped to "String" by default. Override with "TypeRegistry" for richer types.

## Migrations

Create a migration:

```bash
bundle exec rake db:migration[create_users]
```

This generates "db/migrate/20260222120000_create_users.rb":

```ruby
class CreateUsers < HakumiORM::Migration
  def up
    create_table("users") do |t|
      t.string "name", null: false
      t.string "email", null: false, limit: 255
      t.integer "age"
      t.boolean "active", null: false, default: "true"
      t.timestamps
    end

    add_index "users", ["email"], unique: true
  end

  def down
    drop_table "users"
  end
end
```

Run migrations:

```bash
bundle exec rake db:migrate           # run pending
bundle exec rake db:rollback          # rollback last
bundle exec rake db:rollback[3]       # rollback 3
bundle exec rake db:migrate:status    # show up/down status
bundle exec rake db:version           # current version
```

Available DSL methods inside "up"/"down":

| Method | Description |
|---|---|
| "create_table(name, id:)" | Create table. "id:" controls PK type: ":bigserial" (default), ":serial", ":uuid", "false" (no PK). Block yields "TableDefinition". |
| "drop_table(name)" | Drop table. |
| "rename_table(old, new)" | Rename table. |
| "add_column(table, col, type, ...)" | Add column. Options: "null:", "default:", "limit:", "precision:", "scale:". |
| "remove_column(table, col)" | Drop column. |
| "change_column(table, col, type, ...)" | Change column type. |
| "rename_column(table, old, new)" | Rename column. |
| "add_index(table, columns, ...)" | Create index. Options: "unique:", "name:". |
| "remove_index(table, columns, ...)" | Drop index. Options: "name:". |
| "add_foreign_key(from, to, column:, ...)" | Add FK constraint. Options: "primary_key:", "on_delete:" (":cascade", ":set_null", ":restrict"). |
| "remove_foreign_key(from, to, ...)" | Drop FK constraint. Options: "column:". |
| "execute(sql)" | Run raw SQL. |

"TableDefinition" sugar methods: "t.string", "t.text", "t.integer", "t.bigint", "t.float", "t.decimal", "t.boolean", "t.date", "t.datetime", "t.timestamp", "t.binary", "t.json", "t.jsonb", "t.uuid", "t.inet", "t.cidr", "t.hstore", "t.integer_array", "t.string_array", "t.float_array", "t.boolean_array", "t.timestamps", "t.references", "t.primary_key".

"t.references" accepts an optional "column:" keyword for tables with irregular plurals:

```ruby
t.references "people", foreign_key: true, column: "person_id"
```

"t.primary_key" declares a composite primary key on tables with "id: false":

```ruby
create_table("user_roles", id: false) do |t|
  t.integer "user_id", null: false
  t.integer "role_id", null: false
  t.primary_key %w[user_id role_id]
end
```

Column types are validated early -- passing an unknown type raises immediately with a list of all valid types.

Auto-generated identifier names (indexes, foreign key constraints) are validated against dialect limits (PostgreSQL: 63 chars, MySQL: 64 chars) to prevent cryptic database errors.

Migration names are validated on generation -- only lowercase letters, digits, and underscores are accepted.

All SQL is dialect-aware -- the same migration produces correct SQL for PostgreSQL, MySQL, and SQLite.

### DDL transactions

On PostgreSQL and SQLite, each migration runs inside a transaction. If it fails, all changes are rolled back.

On MySQL, DDL statements cause implicit commits -- the Runner detects this via "dialect.supports_ddl_transactions?" and logs a warning.

To opt out of the transaction wrapper (needed for "CREATE INDEX CONCURRENTLY" in PostgreSQL):

```ruby
class AddEmailIndexConcurrently < HakumiORM::Migration
  disable_ddl_transaction!

  def up
    execute "CREATE INDEX CONCURRENTLY idx_users_email ON users (email)"
  end

  def down
    execute "DROP INDEX CONCURRENTLY idx_users_email"
  end
end
```

### Concurrency safety

The migration Runner acquires a database-level advisory lock before running migrations or rollbacks:

- PostgreSQL: "pg_advisory_lock(hash)"
- MySQL: "GET_LOCK(name, timeout)"
- SQLite: no lock needed (single-process)

The lock is always released in an "ensure" block.

### Migration configuration

Migration files are read from "db/migrate" by default. To change:

```ruby
HakumiORM.configure do |c|
  c.migrations_path = "database/migrations"
end
```

## Schema Drift and Pending Migration Detection

HakumiORM protects against running with stale generated code or unapplied migrations. Three layers of detection:

**Boot check (automatic, every app start):**

On first adapter access, HakumiORM performs two checks:

1. **Schema fingerprint** -- Compares the SHA256 fingerprint embedded in the generated manifest against the one stored in "hakumi_schema_meta". Raises "SchemaDriftError" on mismatch.
2. **Pending migrations** -- Scans migration files in "migrations_path" against applied versions in "hakumi_migrations". Raises "PendingMigrationError" if any are unapplied.

```
HakumiORM::PendingMigrationError: 2 pending migration(s): 20260301000001, 20260301000002.
  Run 'rake db:migrate' to apply.
```

Environment variable bypass:

- "HAKUMI_ALLOW_SCHEMA_DRIFT=1" -- skip fingerprint check (emergency only, logs warning instead of raising)

**"db:check" (CI and manual):**

```bash
bundle exec rake db:check
```

Detects both pending migrations and schema drift with detailed output. Exit code 0 = clean, 1 = issues found. Ideal for CI pipelines:

```yaml
- run: bundle exec rake db:migrate
- run: bundle exec rake db:check
```

**Auto-generate after migrate:**

"db:migrate" automatically runs "db:generate" after applying migrations, keeping generated code in sync. Set "HAKUMI_SKIP_GENERATE=1" to skip.

## Connection Pooling

For multi-threaded applications, use "ConnectionPool" instead of a single adapter:

```ruby
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::ConnectionPool.new(size: 10, timeout: 5.0) do
    HakumiORM::Adapter::Postgresql.connect(dbname: "myapp")
  end
end
```

Works with any adapter:

```ruby
# MySQL
require "hakumi_orm/adapter/mysql"
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::Mysql.connect(database: "myapp", host: "localhost", username: "root")
end

# SQLite
require "hakumi_orm/adapter/sqlite"
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::Sqlite.connect("db/myapp.sqlite3")
end
```

The pool implements "Adapter::Base", so it can replace any single adapter without changing application code. Connections are checked out per-thread and reused within nested calls (transactions, etc.). Dead connections are automatically evicted: if a query fails and "alive?" returns false, the connection is discarded and a fresh one is created on the next checkout.

| Option | Default | Description |
|---|---|---|
| "size" | "5" | Maximum number of connections in the pool |
| "timeout" | "5.0" | Seconds to wait for a connection before raising "TimeoutError" |

## Multi-Database Support

Configure named databases for read replicas, analytics, or other secondary databases:

```ruby
HakumiORM.configure do |c|
  c.database_url = ENV.fetch("DATABASE_URL")

  c.database_config(:replica) do |r|
    r.database_url = ENV.fetch("REPLICA_DATABASE_URL")
  end

  c.database_config(:analytics) do |r|
    r.database_url = ENV.fetch("ANALYTICS_DATABASE_URL")
  end
end
```

Named databases also accept individual params:

```ruby
c.database_config(:replica) do |r|
  r.adapter_name = :postgresql
  r.database = "myapp_replica"
  r.host = "replica.host.com"
  r.username = "readonly"
  r.password = ENV.fetch("REPLICA_DB_PASSWORD")
  r.pool_size = 5
end
```

**Block-based switching** -- all queries inside the block use the named adapter:

```ruby
HakumiORM.using(:replica) do
  User.all.to_a
  Article.where(ArticleSchema::PUBLISHED.eq(true)).to_a
end
```

**Per-query switching** -- pass the adapter explicitly:

```ruby
User.all.to_a(adapter: HakumiORM.adapter(:replica))
```

**Nestable** -- blocks can be nested, each level restores the previous adapter:

```ruby
HakumiORM.using(:replica) do
  users = User.all.to_a
  HakumiORM.using(:analytics) do
    AnalyticsEvent.all.to_a
  end
end
```

| Method | Description |
|---|---|
| "HakumiORM.using(:name) { ... }" | Switches adapter for the block (thread-safe, nestable) |
| "HakumiORM.adapter(:name)" | Returns the named adapter directly |
| "config.database_config(:name) { \|r\| ... }" | Registers a named database |
| "config.database_names" | Lists all registered database names |

Each named database gets its own connection pool. No automatic read/write splitting -- the caller decides where to route queries (Hakumi philosophy: explicit, not magic).

## Query Logging

Enable SQL logging to see every query, its bind parameters, and execution time:

```ruby
HakumiORM.configure do |config|
  config.log_level = :debug
end
```

Output:

```
D, [2026-02-22] DEBUG -- : [HakumiORM] (0.42ms) SELECT "users".* FROM "users" WHERE "users"."active" = $1 ["t"]
```

When "pretty_sql_logs" is enabled, output is formatted and transaction statements are tagged:

```
HakumiORM SQL (0.10ms) BEGIN [TRANSACTION]
HakumiORM SQL (1.22ms) INSERT INTO ...
HakumiORM SQL (0.08ms) COMMIT [TRANSACTION]
```

Set to "nil" (default) to disable logging entirely with zero overhead.

For production or advanced use cases, inject any logger that implements "HakumiORM::Loggable" (defines "debug", "info", "warn", "error", "fatal"). Ruby's "::Logger" satisfies this interface out of the box:

```ruby
HakumiORM.configure do |config|
  config.logger = Rails.logger
  config.logger = Logger.new("log/sql.log", "daily")
  config.logger = MyCustomLogger.new
end
```

Available log levels for "log_level=": ":debug", ":info", ":warn", ":error", ":fatal".

Sensitive bind values can be filtered:

```ruby
HakumiORM.configure do |config|
  config.log_filter_parameters = %w[passw email token secret]
  config.log_filter_mask = "[HIDDEN]"
end
```

In Rails integration, HakumiORM automatically reuses "Rails.application.config.filter_parameters".

## Rake Tasks

Add to your "Rakefile":

```ruby
require "hakumi_orm/tasks"
```

Available tasks:

```bash
bundle exec rake db:install                # create initial project structure (dirs, config)
bundle exec rake db:generate           # generate models from DB schema + update annotations
bundle exec rake db:migrate            # run pending migrations + auto-regenerate
bundle exec rake db:rollback[N]        # rollback N migrations
bundle exec rake db:migrate:status     # show migration status
bundle exec rake db:version            # show current schema version
bundle exec rake db:migration[name]    # scaffold new migration
bundle exec rake db:check              # detect schema drift + pending migrations (CI-friendly)
bundle exec rake db:seed               # run seed file (default: db/seeds.rb)
bundle exec rake db:scaffold[table]    # scaffold model + contract for a table
bundle exec rake db:type[name]         # scaffold custom type
bundle exec rake db:associations       # list all associations (FK + custom + through)
bundle exec rake db:associations[name] # list associations for one model
```

## Low-Level Reference

### Type Casting

Raw PostgreSQL strings are converted to Ruby types through a strict "Cast" module:

```ruby
HakumiORM::Cast.integer("42")                         # => 42
HakumiORM::Cast.boolean("t")                          # => true
HakumiORM::Cast.timestamp("2024-01-15 09:30:00.123456") # => Time
HakumiORM::Cast.decimal("99999.00001")                # => BigDecimal
```

Nullable columns use "get_value" (returns "T.nilable(String)"), non-nullable columns use "fetch_value" (returns "String", raises on unexpected NULL).

### CompiledQuery

The result of "to_sql". Contains the raw SQL and bind parameters without executing.

| Method | Returns | Description |
|---|---|---|
| "sql" | "String" | The parameterized SQL string (e.g., "SELECT ... WHERE "age" > $1") |
| "binds" | "T::Array[Bind]" | Array of typed bind objects |
| "pg_params" | "T::Array[PGValue]" | Array of raw values suitable for "PG::Connection#exec_params" |

## Architecture

All source code lives under "lib/hakumi_orm/". Every file is Sorbet "typed: strict". One class per file, except "sealed!" hierarchies ("Bind", "Expr") where all subclasses are co-located for exhaustive "T.absurd" checks.

```
lib/hakumi_orm/
├── adapter/              # Database adapters (PostgreSQL, MySQL, SQLite)
│   ├── base.rb           #   Abstract base, transaction/savepoint support
│   ├── result.rb         #   Abstract result interface
│   ├── postgresql.rb     #   PG::Connection wrapper
│   ├── mysql.rb          #   Mysql2::Client wrapper
│   ├── sqlite.rb         #   SQLite3::Database wrapper
│   ├── connection_pool.rb#   Thread-safe pool (reentrant, configurable)
│   └── timeout_error.rb  #   Pool timeout error
├── dialect/              # SQL dialect abstraction
│   ├── postgresql.rb     #   $1/$2 markers, double-quote quoting
│   ├── mysql.rb          #   ? markers, backtick quoting
│   └── sqlite.rb         #   ? markers, double-quote quoting
├── field/                # Typed field constants (one per file)
│   ├── comparable_field.rb#  gt/gte/lt/lte/between
│   ├── text_field.rb     #   like/ilike
│   ├── int_field.rb, float_field.rb, decimal_field.rb, ...
│   ├── json_field.rb     #   JSON/JSONB field
│   ├── enum_field.rb     #   PG native enums (StrBind)
│   ├── int_enum_field.rb #   User-defined enums (IntBind)
│   └── *_array_field.rb  #   Array fields (int, str, float, bool)
├── codegen/              # Code generation from live schema
│   ├── generator.rb      #   ERB template engine
│   ├── schema_reader.rb  #   PostgreSQL schema reader
│   ├── mysql_schema_reader.rb  # MySQL schema reader
│   ├── sqlite_schema_reader.rb # SQLite schema reader
│   ├── type_registry.rb  #   Custom type registration
│   └── type_maps/        #   DB type → HakumiType per dialect
├── loggable.rb           # Sorbet interface for loggers (::Logger includes it at boot)
├── bind.rb               # Sealed bind hierarchy (13 subclasses, includes array binds)
├── expr.rb               # Sealed expression tree (6 subclasses)
├── sql_compiler.rb       # Expr → parameterized SQL
├── relation.rb           # Fluent query builder
└── ...
```

See ["lib/hakumi_orm/README.md"](lib/hakumi_orm/README.md) for a full reference of every module, class, and public API.

## Development

```bash
bin/setup       # Install dependencies
bin/ci          # Run full CI pipeline locally (rubocop + sorbet + tests)
```

Individual steps:

```bash
bundle exec rake test    # Minitest suite
bundle exec rubocop      # Lint
bundle exec srb tc       # Static type check
```

## Contributing

1. Fork the repository
2. Create your feature branch ("git checkout -b feature/my-feature")
3. Run "bin/ci" to verify all checks pass
4. Commit your changes
5. Open a Pull Request

All contributions must pass RuboCop, Sorbet ("typed: strict"), and the full test suite.

## License

Released under the [MIT License](LICENSE.txt).

<p align="center">
  <a href="https://github.com/hakumi-dev">hakumi-dev</a>
</p>
