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
- **Multi-database support** -- dialect abstraction for PostgreSQL, MySQL, and SQLite

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
app/db/generated/          <-- always overwritten by codegen
  user/
    checkable.rb           # UserRecord::Checkable -- interface for validatable fields
    schema.rb              # UserSchema -- typed Field constants
    record.rb              # UserRecord -- persisted record (all columns, keyword init)
    new_record.rb          # UserRecord::New -- pre-persist record (validate!)
    validated_record.rb    # UserRecord::Validated -- validated record (save!)
    base_contract.rb       # UserRecord::BaseContract -- overridable validation hooks
    variant_base.rb        # UserRecord::VariantBase -- delegation base for user-defined variants
    relation.rb            # UserRelation -- typed query builder
  performance_review/
    ...
    variant_base.rb        # PerformanceReviewRecord::VariantBase
  manifest.rb              # require_relative for all files

app/models/                <-- generated once, never overwritten; yours to edit
  user.rb                  # class User < UserRecord
  post.rb                  # class Post < PostRecord
  performance_review.rb    # class PerformanceReview < PerformanceReviewRecord
  performance_review/      # variant subclasses (user-defined, not codegen)
    draft.rb               # PerformanceReview::Draft < PerformanceReviewRecord::VariantBase
    started.rb             # PerformanceReview::Started < PerformanceReview::Draft
    completed.rb           # PerformanceReview::Completed < PerformanceReview::Started
    cancelled.rb           # PerformanceReview::Cancelled < PerformanceReview::Started
    rejected.rb            # PerformanceReview::Rejected < PerformanceReview::Draft

app/contracts/             <-- generated once, never overwritten
  user_contract.rb         # UserRecord::Contract < UserRecord::BaseContract
  post_contract.rb         # PostRecord::Contract < PostRecord::BaseContract
```

The "models/" files are your public API. They inherit from the generated records and are where you add custom logic:

```ruby
# app/models/user.rb (generated once, then yours to edit)
class User < UserRecord
  def display_name
    "#{name} <#{email}>"
  end

  def published_posts
    posts.where(PostSchema::PUBLISHED.eq(true))
  end
end
```

You interact with "User", not "UserRecord":

```ruby
user = User.find(1)
user.published_posts.to_a
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.validate!.save!
```

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
| Rake task | "rails db:migrate" etc. | "rake hakumi:generate" |
| Dirty tracking | Automatic (mutable) | "diff(other)" / "changed_from?(other)" (immutable snapshots) |
| Timestamps | Automatic "created_at"/"updated_at" | Configurable via "created_at_column" / "updated_at_column" |
| Migrations | Built-in | Built-in: dialect-aware DSL, timestamped files, advisory locks |

## Installation

Add to your application's Gemfile:

```ruby
gem "hakumi-orm"
```

Then run:

```bash
bundle install
```

### Requirements

- Ruby >= 3.2
- Sorbet runtime ("sorbet-runtime" gem, pulled automatically)
- A database driver ("pg", "mysql2", or "sqlite3") depending on your target

## Usage

### Configuration

Configure HakumiORM once at boot -- connection, paths, and adapter are available globally:

```ruby
HakumiORM.configure do |config|
  # Connection (adapter is built lazily from these)
  config.adapter_name = :postgresql          # :postgresql (default), :mysql, :sqlite
  config.database     = "myapp"
  config.host         = "localhost"
  config.port         = 5432
  config.username     = "postgres"
  config.password     = "secret"

  # Paths
  config.output_dir   = "app/db/generated"   # where generated code goes (default)
  config.models_dir    = "app/models"          # where model stubs go (nil = skip)
  config.contracts_dir = "app/contracts"      # where contract stubs go (nil = skip)
  config.module_name   = "App"               # optional namespace wrapping
end
```

The adapter connects automatically when first needed ("HakumiORM.adapter"). You can also set it explicitly:

```ruby
# PostgreSQL
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::Postgresql.connect(dbname: "myapp")
end

# MySQL
require "hakumi_orm/adapter/mysql"
HakumiORM.configure do |config|
  config.adapter_name = :mysql
  config.database     = "myapp"
  config.host         = "localhost"
  config.username     = "root"
end

# SQLite
require "hakumi_orm/adapter/sqlite"
HakumiORM.configure do |config|
  config.adapter_name = :sqlite
  config.database     = "db/myapp.sqlite3"
end
```

| Option | Default | Description |
|---|---|---|
| "adapter_name" | ":postgresql" | Which database adapter to use: ":postgresql", ":mysql", or ":sqlite". |
| "database" | "nil" | Database name. When set, the adapter is built lazily from connection params. |
| "host" | "nil" | Database host. "nil" uses the default (local socket / localhost). |
| "port" | "nil" | Database port. "nil" uses the default (5432 for PostgreSQL). |
| "username" | "nil" | Database user. "nil" uses the current system user. |
| "password" | "nil" | Database password. "nil" for passwordless / peer auth. |
| "adapter" | auto | Set directly to skip lazy building. Takes precedence over connection params. |
| "logger" | "nil" | "Logger" instance for SQL query logging. Logs SQL, binds, and execution time at "DEBUG" level. "nil" = no logging, zero overhead. |
| "output_dir" | ""app/db/generated"" | Directory for generated schemas, records, and relations (always overwritten). |
| "models_dir" | "nil" | Directory for model stubs ("User < UserRecord"). Generated **once**, never overwritten. "nil" = skip. |
| "contracts_dir" | "nil" | Directory for contract stubs ("UserRecord::Contract"). Generated **once**, never overwritten. "nil" = skip. |
| "module_name" | "nil" | Wraps all generated code in a namespace ("App::User", "App::UserRecord", etc.). |
| "migrations_path" | ""db/migrate"" | Directory where migration files are read from and generated into. |

All generated methods ("find", "where", "save!", associations, etc.) default to "HakumiORM.adapter", so you never pass the adapter manually.

### Query Logging

Enable SQL logging to see every query, its bind parameters, and execution time:

```ruby
HakumiORM.configure do |config|
  config.logger = Logger.new($stdout)
end
```

Output:

```
D, [2026-02-22] DEBUG -- : [HakumiORM] (0.42ms) SELECT "users".* FROM "users" WHERE "users"."active" = $1 ["t"]
```

Set to "nil" (default) to disable logging entirely with zero overhead. Uses "Logger#debug" level, so in production you can set "logger.level = Logger::INFO" to silence query logs without removing the logger.

### Code Generation

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

## API Reference

### Record Class Methods

These methods are generated on every record class (e.g., "UserRecord", and inherited by "User").

#### "find(pk_value) -> T.nilable(Record)"

Find a record by primary key. Returns "nil" if not found.

```ruby
user = User.find(42)     # => UserRecord or nil
```

#### "find_by(expr) -> T.nilable(Record)"

Find the first record matching an expression. Sugar for ".where(expr).first".

```ruby
user = User.find_by(UserSchema::EMAIL.eq("alice@example.com"))
```

#### "exists?(expr) -> Boolean"

Check if any record matches. Compiles "SELECT 1 ... LIMIT 1" for efficiency.

```ruby
User.exists?(UserSchema::EMAIL.eq("alice@example.com"))  # => true or false
```

#### "where(expr) -> Relation"

Start a filtered query. Returns a chainable "Relation".

```ruby
User.where(UserSchema::ACTIVE.eq(true))
```

#### "all -> Relation"

Return a "Relation" for all rows in the table.

```ruby
User.all.to_a            # => T::Array[UserRecord]
```

#### "build(...) -> Record::New"

Create a new unpersisted record with keyword arguments. Returns a "Record::New" instance (no "id").

```ruby
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.class           # => UserRecord::New
```

### Record Instance Methods

#### "update!(...) -> Record"

Update a persisted record's attributes. Takes keyword arguments for each column (defaults to current values for unchanged fields). Validates via "Contract.on_all", "Contract.on_update", and "Contract.on_persist", then executes "UPDATE ... RETURNING *". Returns a new hydrated "Record".

```ruby
updated_user = user.update!(name: "Bob", active: false)
updated_user.name        # => "Bob"
updated_user.id          # => same id, guaranteed
```

#### "delete! -> void"

Delete a persisted record by primary key. Raises "HakumiORM::Error" if no rows are affected (record was already deleted).

```ruby
user.delete!
```

#### "reload! -> Record"

Re-fetch the record from the database by primary key. Returns a new "Record" instance with fresh data. Raises if the record no longer exists.

```ruby
fresh = user.reload!
fresh.name               # => current DB value
```

#### "to_h -> Hash"

Convert the record to a hash keyed by column name. The value type is a union of all column types (no "T.untyped").

```ruby
user.to_h
# => { id: 1, name: "Alice", email: "alice@example.com", age: 25, active: true }
```

### Record::New Instance Methods

#### "validate! -> Record::Validated"

Run "Contract.on_all" and "Contract.on_create" validations. Returns an immutable "Record::Validated" on success, raises "ValidationError" on failure.

```ruby
validated = new_user.validate!
validated.class          # => UserRecord::Validated
```

### Record::Validated Instance Methods

#### "save!(adapter: HakumiORM.adapter) -> Record"

Run "Contract.on_persist" validations, then persist via "INSERT ... RETURNING *". Returns a fully hydrated "Record" with "id". If the table has "created_at" / "updated_at" timestamp columns, they are automatically set to "Time.now".

```ruby
user = validated.save!
user.id                  # => Integer (guaranteed)
user.created_at          # => Time (auto-set)
```

### Relation Methods

"Relation" is a chainable, lazy query builder. Nothing hits the database until a terminal method ("to_a", "first", "count", etc.) is called.

#### Chainable (return "self")

| Method | Description |
|---|---|
| "where(expr)" | Add a WHERE condition. Multiple calls are ANDed. |
| "where_raw(sql, binds)" | Add a raw SQL WHERE fragment with "?" bind placeholders. |
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

#### Terminal (execute the query)

| Method | Returns | Description |
|---|---|---|
| "to_a" | "T::Array[Record]" | Execute and return all matching records. |
| "first" | "T.nilable(Record)" | Execute with LIMIT 1 and return the first record. |
| "count" | "Integer" | Execute "SELECT COUNT(*)" and return the count. |
| "exists?" | "T::Boolean" | Execute "SELECT 1 ... LIMIT 1" and return whether any row matches. |
| "pluck_raw(field)" | "T::Array[T.nilable(String)]" | Return raw string values for a single column. |
| "delete_all" | "Integer" | Execute "DELETE" and return the number of deleted rows. |
| "update_all(assignments)" | "Integer" | Execute "UPDATE" and return the number of updated rows. |
| "to_sql" | "CompiledQuery" | Return the compiled SQL + binds **without executing**. |
| "sum(field)" | "T.nilable(String)" | Execute "SELECT SUM(field)" and return the result. |
| "average(field)" | "T.nilable(String)" | Execute "SELECT AVG(field)" and return the result. |
| "minimum(field)" | "T.nilable(String)" | Execute "SELECT MIN(field)" and return the result. |
| "maximum(field)" | "T.nilable(String)" | Execute "SELECT MAX(field)" and return the result. |
| "pluck(*fields)" | "T::Array[T::Array[T.nilable(String)]]" | Multi-column pluck returning raw string arrays. |

```ruby
# Execute
users = User.all.to_a
first = User.all.order(UserSchema::NAME.asc).first

# Aggregate
total = User.where(UserSchema::ACTIVE.eq(true)).count
total_age = User.all.sum(UserSchema::AGE)
avg_age = User.all.average(UserSchema::AGE)
youngest = User.all.minimum(UserSchema::AGE)
oldest = User.all.maximum(UserSchema::AGE)

# Multi-column pluck
pairs = User.all.pluck(UserSchema::NAME, UserSchema::EMAIL)
# => [["Alice", "a@b.com"], ["Bob", "b@c.com"]]

# Pluck raw values (single column)
names = User.all.order(UserSchema::NAME.asc).pluck_raw(UserSchema::NAME)
# => ["Alice", "Bob", "Carol"]

# Inspect SQL without executing
compiled = User.where(UserSchema::AGE.gt(18)).to_sql
compiled.sql     # => 'SELECT ... WHERE "users"."age" > $1'
compiled.binds   # => [#<IntBind value=18>]

# Bulk update
User
  .where(UserSchema::ACTIVE.eq(false))
  .update_all([HakumiORM::Assignment.new(UserSchema::ACTIVE, HakumiORM::BoolBind.new(true))])
# => 1 (number of updated rows)

# Bulk delete
User.where(UserSchema::NAME.eq("temp")).delete_all
# => 1 (number of deleted rows)

# Distinct query
User.all.distinct.pluck(UserSchema::NAME)

# Group + aggregate
User.all.group(UserSchema::ACTIVE).to_a

# Pessimistic locking
User.where(UserSchema::ID.eq(1)).lock.first
# => SELECT ... WHERE ... FOR UPDATE

# Raw SQL escape hatch
User.all.where_raw(
  "LENGTH(\"users\".\"name\") > ?",
  [HakumiORM::IntBind.new(5)]
).to_a

# Subquery
sub = compiler.select(table: "orders", columns: [OrderSchema::USER_ID])
User.where(HakumiORM::SubqueryExpr.new(UserSchema::ID, :in, sub)).to_a
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

Multiple ".where" calls are ANDed automatically, so the most common case needs no explicit combinator:

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

#### Operator aliases

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

### Associations

Associations are generated automatically from foreign keys. No manual declaration needed.

#### "has_many" (one-to-many)

Returns a **lazy "Relation"** -- no query is executed until a terminal method is called. The relation is fully chainable.

```ruby
alice = User.find(1)

alice.posts                  # => PostRelation (no query yet)
alice.posts.to_a             # => T::Array[PostRecord] (executes SELECT)
alice.posts.count            # => Integer (executes SELECT COUNT(*))

# Chain filters on the association
alice.posts
  .where(PostSchema::PUBLISHED.eq(true))
  .order(PostSchema::TITLE.asc)
  .to_a
```

#### "has_one" (one-to-one)

Generated when the FK column on the child table has a UNIQUE constraint. Returns "T.nilable(Record)".

```ruby
alice = User.find(1)
alice.profile                # => T.nilable(ProfileRecord) (executes SELECT ... LIMIT 1)
```

#### "belongs_to" (many-to-one)

Returns the related record by executing a "find" on the foreign key value.

```ruby
post = Post.find(1)
post.user                    # => T.nilable(UserRecord) (executes SELECT)
```

#### "has_many :through" (transitive associations)

Generated automatically for FK chains and join tables. Uses "SubqueryExpr" internally.

```ruby
# Join table: users_roles (user_id, role_id) -> User has_many :roles through :users_roles
alice = User.find(1)
alice.roles                  # => RoleRelation (subquery: WHERE id IN (SELECT role_id FROM users_roles WHERE user_id = ?))
alice.roles.to_a             # => T::Array[RoleRecord]

# Chain pattern: users -> posts -> comments -> User has_many :comments through :posts
alice.comments               # => CommentRelation (subquery)
alice.comments.where(CommentSchema::APPROVED.eq(true)).to_a
```

#### Preloading (eager loading)

Use "preload" to batch-load associations in a single extra query:

```ruby
# 2 queries total: SELECT * FROM users; SELECT * FROM posts WHERE user_id IN (1, 2, 3)
users = User.all.preload(:posts).to_a

users.each do |u|
  puts u.posts.count             # no query -- data is already loaded
end
```

Nested preloads load associations recursively:

```ruby
# 3 queries: users, posts, comments
users = User.all.preload(posts: :comments).to_a

users.each do |u|
  u.posts.to_a.each do |p|
    p.comments.to_a              # no query -- already loaded
  end
end

# Multiple nested
User.all.preload(:profile, posts: [:comments, :tags]).to_a
```

"preload" works for "has_many", "has_one", and "belongs_to".

#### Custom Associations (non-FK based)

FK-based associations are generated from the schema automatically. For associations based on a different column match (email, slug, external_id), declare them in "db/associations/" and the generator produces everything -- lazy accessor, batch preload, cache, and dispatch. Zero boilerplate in your model file.

One file per source table:

```ruby
# db/associations/users.rb
# frozen_string_literal: true

HakumiORM.associate("users") do |a|
  a.has_many "authored_articles", target: "articles", foreign_key: "author_email", primary_key: "email"
  a.has_one  "latest_comment",    target: "comments", foreign_key: "user_email",   primary_key: "email", order_by: "created_at"
end
```

The generator produces the same code as FK-based associations. No distinction in the generated output:

```ruby
alice = User.find(1)

alice.posts                    # FK-based has_many (generated from schema)
alice.authored_articles        # Custom has_many (generated from config)
alice.latest_comment           # Custom has_one with ordering (generated from config)

# Chainable -- returns a Relation, not an array
alice.authored_articles.where(ArticleSchema::PUBLISHED.eq(true)).count

# Preloadable -- batch loading in a single extra query
users = User.all.preload(:posts, :authored_articles, :latest_comment).to_a
users.each do |u|
  u.authored_articles.to_a   # no query -- already preloaded
  u.latest_comment            # no query -- already preloaded
end
```

Available methods inside the "associate" block:

| Method | Required fields | Description |
|---|---|---|
| "has_many" | "name", "target:", "foreign_key:", "primary_key:" | Returns a Relation (lazy, chainable). |
| "has_one" | "name", "target:", "foreign_key:", "primary_key:" | Returns "T.nilable(Record)". Optional "order_by:" for deterministic results (always DESC). |

The generator validates at codegen time: tables and columns must exist, source column must be NOT NULL, types must be compatible (both strings, both integers, etc.), names must not collide with existing associations or columns. Errors are raised during "rake hakumi:generate" with clear messages.

The associations directory is configurable:

```ruby
HakumiORM.configure do |c|
  c.associations_path = "db/associations"  # default
end
```

#### Model Annotations

"hakumi:generate" auto-updates a comment block at the top of each model file showing columns, types, and ALL associations (FK + custom + through). The user code below the annotation is never touched:

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

The generator looks for the "# == Schema Information ==" / "# == End Schema Information ==" markers and replaces only that block. If no markers exist (first run), the block is prepended.

You can also list all associations from the command line:

```bash
bundle exec rake hakumi:associations            # all models
bundle exec rake hakumi:associations[users]     # single model
```

#### Custom Associations (escape hatch)

For associations that cannot be expressed as a field match (multi-step subqueries, external APIs, composite keys, polymorphic patterns), override "custom_preload" in the Relation manually:

```ruby
# app/models/user.rb
class User < UserRecord
  extend T::Sig

  sig { returns(T::Array[AuditRecord]) }
  def recent_audits
    AuditRelation.new.where(AuditSchema::ENTITY_TYPE.eq("user").and(AuditSchema::ENTITY_ID.eq(id.to_s))).to_a
  end
end

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

#### When to Regenerate

| Action | Requires regeneration? |
|---|---|
| Run a migration (add/remove column, table, FK) | Yes (automatic if using "hakumi:migrate") |
| Add/change a custom association in "db/associations/" | Yes |
| Add a scope to a Relation | No |
| Edit a Contract hook | No |
| Override "custom_preload" (escape hatch) | No |
| Change "GeneratorOptions" (soft delete, timestamps) | Yes |

Regeneration also updates model annotations ("# == Schema Information ==" block) with the latest schema and associations.

#### Dependent delete/destroy

When deleting a parent record, you can cascade to associated records:

```ruby
# :delete_all -- batch SQL DELETE on children (no callbacks)
user.delete!(dependent: :delete_all)

# :destroy -- loads children and calls delete! on each (cascades recursively)
user.delete!(dependent: :destroy)

# :none (default) -- no cascade, relies on DB constraints
user.delete!
```

The "dependent" parameter is only generated when the record has "has_many" or "has_one" associations.

### Connection Pooling

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

The pool implements "Adapter::Base", so it's a transparent drop-in. Connections are checked out per-thread and reused within nested calls (transactions, etc.).

| Option | Default | Description |
|---|---|---|
| "size" | "5" | Maximum number of connections in the pool |
| "timeout" | "5.0" | Seconds to wait for a connection before raising "TimeoutError" |

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

### Optimistic Locking

If a table has a "lock_version" integer column, the codegen automatically:
- Adds "lock_version = lock_version + 1" to every "UPDATE"
- Adds "WHERE lock_version = $current" to prevent stale writes
- Excludes "lock_version" from "update!" user parameters
- Raises "StaleObjectError" if the row was modified by another process

```ruby
user = User.find(1)

# Another process updates the same user...
other = User.find(1)
other.update!(name: "Other")

# This raises StaleObjectError because lock_version no longer matches
user.update!(name: "Stale")  # => HakumiORM::StaleObjectError
```

### JSON/JSONB Columns

JSON and JSONB columns are automatically mapped to "HakumiORM::Json". The "Json" class stores the raw JSON string internally and provides typed accessors -- zero "Object", zero "T.untyped":

```ruby
event = Event.find(1)
event.payload            # => HakumiORM::Json

# Navigate nested structures -- [] and at return T.nilable(Json)
event.payload["key"]           # => T.nilable(Json)
event.payload["nested"]["deep"]  # => T.nilable(Json)
event.payload.at(0)            # => T.nilable(Json)

# Extract typed scalars
event.payload["name"]&.as_s   # => T.nilable(String)
event.payload["count"]&.as_i  # => T.nilable(Integer)
event.payload["rate"]&.as_f   # => T.nilable(Float)
event.payload["active"]&.as_bool  # => T.nilable(T::Boolean)
event.payload["count"]&.scalar    # => JsonScalar (union of all primitives)

# Serialize back to JSON string
event.payload.to_json          # => String
event.payload.raw_json         # => String (same)

# Creating with JSON data
Event.build(
  name: "signup",
  payload: HakumiORM::Json.from_hash({ "source" => "web", "ip" => "1.2.3.4" })
)

# From arrays
HakumiORM::Json.from_array([1, 2, 3])
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
bundle exec rake hakumi:type[money]
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

The Field converts your Ruby type to a Bind that the DB understands. Zero "T.untyped" -- the custom type is a Ruby abstraction; the DB wire always carries a typed scalar:

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

"cast_expression" is a lambda that produces Ruby source code. It does not run at runtime -- it runs once during "rake hakumi:generate" and the string it returns is written directly into the generated file.

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

When the generator finds a column "price" of type "money_col", it calls your lambda with the raw expression (e.g. "row[3]") and writes the result into the generated record:

```ruby
# generated record.rb (non-nullable column)
obj.instance_variable_set(:@price, Money.from_decimal(row[3]))

# generated record.rb (nullable column)
obj.instance_variable_set(:@price, ((_hv = row[3]).nil? ? nil : Money.from_decimal(_hv)))
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

### Migrations

Create a migration:

```bash
bundle exec rake hakumi:migration[create_users]
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
bundle exec rake hakumi:migrate           # run pending
bundle exec rake hakumi:rollback          # rollback last
bundle exec rake hakumi:rollback[3]       # rollback 3
bundle exec rake hakumi:migrate:status    # show up/down status
bundle exec rake hakumi:version           # current version
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

Migration names are validated on generation -- only lowercase letters, digits, and underscores are accepted. Names starting with digits or containing hyphens/spaces are rejected with a clear error.

All SQL is dialect-aware -- the same migration produces correct SQL for PostgreSQL, MySQL, and SQLite.

#### DDL transactions

On PostgreSQL and SQLite, each migration runs inside a transaction. If it fails, all changes are rolled back.

On MySQL, DDL statements cause implicit commits -- the Runner detects this via "dialect.supports_ddl_transactions?" and logs a warning. Partial rollback is not guaranteed.

To opt out of the transaction wrapper (needed for operations like "CREATE INDEX CONCURRENTLY" in PostgreSQL):

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

#### Concurrency safety

The migration Runner acquires a database-level advisory lock before running migrations or rollbacks. This prevents two processes from executing migrations simultaneously:

- PostgreSQL: "pg_advisory_lock(hash)"
- MySQL: "GET_LOCK(name, timeout)"
- SQLite: no lock needed (single-process)

The lock is always released in an "ensure" block.

#### Configuration

Migration files are read from "db/migrate" by default. To change:

```ruby
HakumiORM.configure do |c|
  c.migrations_path = "database/migrations"
end
```

### Rake Tasks

Add to your "Rakefile":

```ruby
require "hakumi_orm/tasks"
```

Available tasks:

```bash
bundle exec rake hakumi:generate           # generate models from DB schema + update annotations
bundle exec rake hakumi:migrate            # run pending migrations
bundle exec rake hakumi:rollback[N]        # rollback N migrations
bundle exec rake hakumi:migrate:status     # show migration status
bundle exec rake hakumi:version            # show current schema version
bundle exec rake hakumi:migration[name]    # scaffold new migration
bundle exec rake hakumi:type[name]         # scaffold custom type
bundle exec rake hakumi:associations       # list all associations (FK + custom + through)
bundle exec rake hakumi:associations[name] # list associations for one model
```

### Joins

Use "join" to filter records based on related table conditions. The join is for filtering only -- the SELECT returns the main table's columns.

```ruby
# Find users who have at least one published post
join = HakumiORM::JoinClause.new(:inner, "posts", UserSchema::ID, PostSchema::USER_ID)
users = User.all
  .join(join)
  .where(PostSchema::PUBLISHED.eq(true))
  .order(UserSchema::NAME.asc)
  .to_a
```

Supported join types: ":inner", ":left", ":right", ":cross".

### Creating Records

```ruby
# Build a new (unpersisted) record
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.name    # => "Alice"
new_user.class   # => UserRecord::New (no id attribute)

# Validate it -- runs on_all + on_create contract hooks
validated = new_user.validate!
validated.class  # => UserRecord::Validated (immutable)

# Persist it -- runs on_persist, then INSERT RETURNING * hydrates a full record
user = validated.save!
user.class       # => UserRecord
user.id          # => Integer (guaranteed non-nil)
```

### Updating Records

```ruby
# Update specific fields -- unchanged fields default to current values
updated = user.update!(name: "Bob", active: false)
updated.name     # => "Bob"
updated.active   # => false
updated.email    # => unchanged from original

# Validation runs automatically (on_all + on_update + on_persist)
user.update!(name: "")  # raises ValidationError if contract rejects blank names
```

If the table has an "updated_at" timestamp column, it is automatically set to "Time.now" on every "update!" call.

### Deleting Records

```ruby
# Delete a single record by primary key
user.delete!             # => void (raises if record doesn't exist)

# Bulk delete via Relation
User.where(UserSchema::ACTIVE.eq(false)).delete_all  # => Integer (rows deleted)
```

### Soft Delete

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

### Automatic Timestamps

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

### Custom Models

Generated code lives in "app/db/generated/" and is always overwritten. Your models live in "app/models/" and are never touched after the initial stub generation:

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

### Contracts and Lifecycle Hooks

Each model has a Contract that controls its entire lifecycle. Contracts are generated once in "contracts_dir" and never overwritten -- they are yours to edit.

The Contract is the **single place** for all lifecycle logic. Two kinds of hooks:

- **"on_*" hooks** run **before** the operation. They receive an "Errors" object and can **prevent** the operation by adding errors (raises "ValidationError").
- **"after_*" hooks** run **after** the operation succeeds. They receive the persisted "Record" + "Adapter" for side effects. They **cannot** prevent the operation.

#### Execution order per operation

**"validate!" (New -> Validated):**

```
1. Contract.on_all(record, errors)       -- shared validation
2. Contract.on_create(record, errors)    -- create-specific validation
3. raise ValidationError if errors       -- STOPS here on failure
4. return Validated
```

**"save!" (Validated -> Record, executes INSERT):**

```
1. Contract.on_all(record, errors)       -- shared validation
2. Contract.on_persist(record, adapter, errors)  -- DB-dependent validation
3. raise ValidationError if errors       -- STOPS here, no INSERT
4. INSERT ... RETURNING *                -- executes SQL
5. raise Error if no rows returned       -- STOPS here, no after_create
6. Contract.after_create(record, adapter) -- side effects (record is persisted)
7. return Record
```

**"update!" (Record -> Record, executes UPDATE):**

```
1. Contract.on_all(record, errors)       -- shared validation
2. Contract.on_update(record, errors)    -- update-specific validation
3. Contract.on_persist(record, adapter, errors)  -- DB-dependent validation
4. raise ValidationError if errors       -- STOPS here, no UPDATE
5. UPDATE ... RETURNING *                -- executes SQL
6. raise Error/StaleObjectError if no rows -- STOPS here, no after_update
7. Contract.after_update(record, adapter) -- side effects (record is updated)
8. return Record
```

**"delete!" (Record -> void, executes DELETE or soft-delete UPDATE):**

```
1. Contract.on_destroy(record, errors)   -- can prevent deletion
2. raise ValidationError if errors       -- STOPS here, no DELETE
3. DELETE FROM ... WHERE pk = $1         -- executes SQL
4. raise Error if 0 rows affected        -- STOPS here, no after_destroy
5. Contract.after_destroy(record, adapter) -- side effects (record is deleted)
```

#### Contract example

```ruby
# app/contracts/user_contract.rb
class UserRecord::Contract < UserRecord::BaseContract
  extend T::Sig

  sig { override.params(record: UserRecord::Checkable, e: ::HakumiORM::Errors).void }
  def self.on_all(record, e)
    e.add(:name, "cannot be blank") if record.name.strip.empty?
    e.add(:email, "must contain @") unless record.email.include?("@")
  end

  sig { override.params(record: UserRecord::New, e: ::HakumiORM::Errors).void }
  def self.on_create(record, e)
    e.add(:email, "is reserved") if record.email.end_with?("@system.internal")
  end

  sig { override.params(record: UserRecord::Checkable, e: ::HakumiORM::Errors).void }
  def self.on_update(record, e)
    # prevent deactivating admin accounts, etc.
  end

  sig { override.params(record: UserRecord::Checkable, adapter: ::HakumiORM::Adapter::Base, e: ::HakumiORM::Errors).void }
  def self.on_persist(record, adapter, e)
    # check uniqueness, FK existence, etc.
  end

  sig { override.params(record: UserRecord, e: ::HakumiORM::Errors).void }
  def self.on_destroy(record, e)
    e.add(:base, "admins cannot be deleted") if record.admin?
  end

  sig { override.params(record: UserRecord, adapter: ::HakumiORM::Adapter::Base).void }
  def self.after_create(record, adapter)
    AuditLog.record!("user_created", record.id, adapter: adapter)
  end

  sig { override.params(record: UserRecord, adapter: ::HakumiORM::Adapter::Base).void }
  def self.after_update(record, adapter)
    AuditLog.record!("user_updated", record.id, adapter: adapter)
  end

  sig { override.params(record: UserRecord, adapter: ::HakumiORM::Adapter::Base).void }
  def self.after_destroy(record, adapter)
    SearchIndex.remove(record.id, adapter: adapter)
  end
end
```

When any "on_*" hook adds errors, a "ValidationError" is raised:

```ruby
begin
  new_user.validate!
rescue HakumiORM::ValidationError => e
  e.errors.messages  # => { name: ["cannot be blank"], email: ["must contain @"] }
  e.errors.count     # => 2
end
```

#### Hook reference

| Hook | Operation | Timing | Can prevent? | Receives |
|---|---|---|---|---|
| "on_all" | "validate!", "save!", "update!" | Before SQL | Yes | "Checkable", "Errors" |
| "on_create" | "validate!" | Before SQL | Yes | "New", "Errors" |
| "on_update" | "update!" | Before SQL | Yes | "Checkable", "Errors" |
| "on_persist" | "save!", "update!" | Before SQL | Yes | "Checkable", "Adapter", "Errors" |
| "on_destroy" | "delete!" | Before SQL | Yes | "Record", "Errors" |
| "after_create" | "save!" | After INSERT | No | "Record", "Adapter" |
| "after_update" | "update!" | After UPDATE | No | "Record", "Adapter" |
| "after_destroy" | "delete!" | After DELETE | No | "Record", "Adapter" |

### Transaction Hooks

For side effects that must wait until the transaction commits (emails, background jobs, external APIs):

```ruby
adapter.transaction do |txn|
  user = validated.save!

  txn.after_commit { WelcomeMailer.deliver(user.email) }
  txn.after_rollback { ErrorTracker.log("user creation failed") }
end
```

Execution order:

```
1. BEGIN
2. ... your code (INSERT, UPDATE, etc.) ...
3. COMMIT (or ROLLBACK on exception)
4. after_commit callbacks fire (in registration order) -- only if COMMIT succeeded
   OR
4. after_rollback callbacks fire -- only if ROLLBACK happened
5. Callbacks are cleared (never fire twice)
```

- "after_commit" fires after COMMIT, not during the transaction
- "after_rollback" fires after ROLLBACK
- Callbacks registered inside savepoints fire after the **top-level** transaction completes
- Multiple callbacks fire in registration order
- Zero overhead when not used -- no arrays allocated until "after_commit" is called

### Record Variants

In a typical ORM, every nullable column is "T.nilable(X)" everywhere. If your "performance_reviews" table has "score integer NULL", then "review.score" is always "T.nilable(Integer)" -- even when your business logic guarantees it's present for completed reviews. You end up sprinkling "T.must" or nil checks everywhere.

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

The "T.let" here is **not a cast** -- "score" is already "Integer" by the method signature. Sorbet verifies this statically. If someone tries to pass "nil", it's a **compile-time error**, not a runtime crash.

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

After "return nil unless s && ca", Sorbet knows both locals are non-nil. The "Completed.new" call is statically verified to pass the correct types. No casts, no "T.must".

Before and after:

```ruby
review = PerformanceReview.find(1)
review.score              # => T.nilable(Integer) -- Sorbet forces you to handle nil

completed = review.as_completed!
completed.score           # => Integer -- guaranteed non-nil, statically verified
completed.completed_at    # => Time
completed.title           # => String (delegated via VariantBase)
```

Variants can form a **progressive inheritance chain** that models domain progression. Each level only declares what it narrows; parent narrowings are inherited:

```ruby
# Draft → base (no narrowing)
class PerformanceReview::Draft < PerformanceReviewRecord::VariantBase
end

# Started → narrows started_at
class PerformanceReview::Started < PerformanceReview::Draft
  sig { returns(Time) }
  attr_reader :started_at

  sig { params(record: PerformanceReviewRecord, started_at: Time).void }
  def initialize(record:, started_at:)
    super(record: record)
    @started_at = T.let(started_at, Time)
  end
end

# Completed → inherits started_at from Started, narrows score + completed_at
class PerformanceReview::Completed < PerformanceReview::Started
  sig { returns(Integer) }
  attr_reader :score

  sig { returns(Time) }
  attr_reader :completed_at

  sig { params(record: PerformanceReviewRecord, started_at: Time, score: Integer, completed_at: Time).void }
  def initialize(record:, started_at:, score:, completed_at:)
    super(record: record, started_at: started_at)
    @score = T.let(score, Integer)
    @completed_at = T.let(completed_at, Time)
  end
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

"Completed" and "Cancelled" both inherit from "Started" (both have "started_at"), but "Rejected" branches from "Draft" directly. Sorbet enforces this: a "Rejected" is **not** a "Started", and the type checker prevents you from treating it as one.

Key points:
- **Real static typing** -- variant constructors demand non-nil kwargs; Sorbet verifies call sites at compile time
- **No "T.must"** -- "T.let" in constructors is a declaration, not a cast (types already match)
- **No metaprogramming** -- you write the variant classes yourself, full control
- **Progressive inheritance** -- variants chain ("Completed < Started < Draft"), narrowing accumulates
- **Branching** -- model tree-shaped domain logic, not just linear state machines
- **"typed: strict"** -- every file, every variant, fully verified
- **"VariantBase" is codegen** -- mechanical delegation of all columns, always regenerated, never edited

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
│   └── *_array_field.rb  #   Array fields (int, str, float, bool)
├── codegen/              # Code generation from live schema
│   ├── generator.rb      #   ERB template engine
│   ├── schema_reader.rb  #   PostgreSQL schema reader
│   ├── mysql_schema_reader.rb  # MySQL schema reader
│   ├── sqlite_schema_reader.rb # SQLite schema reader
│   ├── type_registry.rb  #   Custom type registration
│   └── type_maps/        #   DB type → HakumiType per dialect
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

### Integration Testing

A "sandbox/" directory (gitignored) lets you test against a real PostgreSQL database:

```bash
createdb hakumi_sandbox
bundle exec ruby sandbox/smoke_test.rb
```

This connects to a local database, creates tables, runs the code generator, loads the generated files, and exercises the full API: all predicates, relation methods, CRUD, associations, preloading, joins, and mutations.

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
