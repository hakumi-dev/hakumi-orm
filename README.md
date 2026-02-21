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

HakumiORM generates fully typed models, query builders, and hydration code directly from your database schema. Every generated file is Sorbet `typed: strict` with **zero** `T.untyped`, `T.unsafe`, or `T.must` in the output.

No `method_missing`. No `define_method`. No runtime reflection for column access.

### Design Principles

- **100% statically typed** -- Sorbet `typed: strict` across the entire codebase
- **Codegen over convention** -- models are generated from your schema, not inferred at runtime
- **Minimal allocations** -- designed for low GC pressure and YJIT-friendly object layouts
- **Prepared statements only** -- all values go through bind parameters, never interpolated into SQL
- **No Arel dependency** -- SQL is built directly from a typed expression tree with sequential bind markers
- **Pre-persist vs persisted types** -- `UserRecord::New` (without `id`) and `UserRecord` (with `id`) are distinct types
- **Multi-database support** -- dialect abstraction for PostgreSQL, MySQL, and SQLite

## Quick Look

```ruby
active_users = User
  .where(UserSchema::ACTIVE.eq(true))
  .order(UserSchema::NAME.asc)
  .limit(25)
  .offset(50)
  .to_a
```

Every field constant knows its type at compile time. `IntField` exposes `gt`, `lt`, `between` but not `like`. `StrField` exposes `like`, `ilike` but not `gt`. `BoolField` exposes neither. Sorbet catches type mismatches **before runtime**:

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
    schema.rb              # UserSchema -- typed Field constants
    record.rb              # UserRecord -- persisted record (all columns, keyword init)
    new_record.rb          # UserRecord::New -- pre-persist record (no id, save!)
    relation.rb            # UserRelation -- typed query builder
  post/
    schema.rb
    record.rb
    new_record.rb
    relation.rb
  manifest.rb              # require_relative for all files

app/models/                <-- generated once, never overwritten
  user.rb                  # class User < UserRecord
  post.rb                  # class Post < PostRecord
```

The `models/` files are your public API. They inherit from the generated records and are where you add custom logic:

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

You interact with `User`, not `UserRecord`:

```ruby
user = User.find(1)
user.published_posts.to_a
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.save!
```

### Querying

```ruby
# ActiveRecord
User.where(active: true).where("age > ?", 18).order(:name).limit(10)
User.where("email LIKE ?", "%@gmail.com")  # raw SQL strings, no type checking

# HakumiORM
User
  .where(UserSchema::ACTIVE.eq(true).and(UserSchema::AGE.gt(18)))
  .order(UserSchema::NAME.asc)
  .limit(10)

User.where(UserSchema::EMAIL.like("%@gmail.com"))
```

Key differences:
- AR uses hash conditions and raw SQL strings -- typos and type mismatches are caught at runtime (or not at all)
- HakumiORM uses typed `Field` objects -- Sorbet catches column name typos, wrong value types, and invalid operations at compile time

### Creating records

```ruby
# ActiveRecord
user = User.new(name: "Alice", email: "alice@example.com")
user.id    # => nil (before save)
user.save! # => true
user.id    # => 1 (after save)
# The same object changes state. `id` is T.nilable(Integer) everywhere.

# HakumiORM
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
# new_user is UserRecord::New -- no `id` attribute at all
# new_user.id  # => Sorbet error: method 'id' does not exist on UserRecord::New

user = new_user.save!
# user is UserRecord -- `id` is Integer, guaranteed non-nil
user.id    # => 1 (always present, never nil)
```

The type system enforces the lifecycle: you **cannot** accidentally access `id` before persistence, and you **cannot** get a `nil` id after persistence.

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

Associations are generated automatically from foreign keys. `has_many` returns a typed `Relation`, `belongs_to` returns the related record.

### Full comparison table

| | ActiveRecord | HakumiORM |
|---|---|---|
| Typing | Runtime, mostly untyped | `typed: strict`, Sorbet-verified |
| Column access | `method_missing` / dynamic | Generated `attr_reader` with `sig` |
| Column names | Strings/symbols, checked at runtime | `Schema::FIELD` constants, checked at compile time |
| Query DSL | Strings / hash conditions | `Field[T]` objects with type-safe operations |
| SQL generation | Arel (dynamic AST) | `SqlCompiler` with sequential bind markers |
| Hydration | Reflection + type coercion | Generated positional `fetch_value` |
| New vs persisted | Same class, `id` is nilable | Two distinct types: `Record::New` and `Record` |
| Associations | Declared via DSL macros | Generated from foreign keys |
| Eager loading | `includes` / `preload` / `eager_load` | Not yet |
| Callbacks | Before/after hooks | None (explicit control flow) |
| Dirty tracking | Automatic | None (opt-in if needed) |
| Migrations | Built-in | Not included (use standalone tools) |

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
- Sorbet runtime (`sorbet-runtime` gem, pulled automatically)
- A database driver (`pg`, `mysql2`, or `sqlite3`) depending on your target

## Usage

### Configuration

Configure HakumiORM once at boot -- connection, paths, and adapter are available globally:

```ruby
HakumiORM.configure do |config|
  # Connection (adapter is built lazily from these)
  config.adapter_name = :postgresql          # :postgresql (default), :mysql, :sqlite planned
  config.database     = "myapp"
  config.host         = "localhost"
  config.port         = 5432
  config.username     = "postgres"
  config.password     = "secret"

  # Paths
  config.output_dir   = "app/db/generated"   # where generated code goes (default)
  config.models_dir   = "app/models"         # where model stubs go (nil = skip)
  config.module_name  = "App"                # optional namespace wrapping
end
```

The adapter connects automatically when first needed (`HakumiORM.adapter`). You can also set it explicitly:

```ruby
HakumiORM.configure do |config|
  config.adapter = HakumiORM::Adapter::Postgresql.connect(dbname: "myapp")
end
```

| Option | Default | Description |
|---|---|---|
| `adapter_name` | `:postgresql` | Which database adapter to use. Currently: `:postgresql`. Planned: `:mysql`, `:sqlite`. |
| `database` | `nil` | Database name. When set, the adapter is built lazily from connection params. |
| `host` | `nil` | Database host. `nil` uses the default (local socket / localhost). |
| `port` | `nil` | Database port. `nil` uses the default (5432 for PostgreSQL). |
| `username` | `nil` | Database user. `nil` uses the current system user. |
| `password` | `nil` | Database password. `nil` for passwordless / peer auth. |
| `adapter` | auto | Set directly to skip lazy building. Takes precedence over connection params. |
| `output_dir` | `"app/db/generated"` | Directory for generated schemas, records, and relations (always overwritten). |
| `models_dir` | `nil` | Directory for model stubs (`User < UserRecord`). Generated **once**, never overwritten. `nil` = skip. |
| `module_name` | `nil` | Wraps all generated code in a namespace (`App::User`, `App::UserRecord`, etc.). |

All generated methods (`find`, `where`, `save!`, associations, etc.) default to `HakumiORM.adapter`, so you never pass the adapter manually.

### Code Generation

Generate model files from your live database schema:

```ruby
reader = HakumiORM::Codegen::SchemaReader.new(HakumiORM.adapter)
tables = reader.read_tables

generator = HakumiORM::Codegen::Generator.new(tables)
generator.generate!
```

The generator reads `output_dir`, `models_dir`, and `module_name` from the global config. You can still override per-call:

```ruby
generator = HakumiORM::Codegen::Generator.new(
  tables,
  dialect:     custom_dialect,
  output_dir:  "custom/path",
  models_dir:  "custom/models",
  module_name: "MyApp"
)
```

## API Reference

### Record Class Methods

These methods are generated on every record class (e.g., `UserRecord`, and inherited by `User`).

#### `find(pk_value) -> T.nilable(Record)`

Find a record by primary key. Returns `nil` if not found.

```ruby
user = User.find(42)     # => UserRecord or nil
```

#### `where(expr) -> Relation`

Start a filtered query. Returns a chainable `Relation`.

```ruby
User.where(UserSchema::ACTIVE.eq(true))
```

#### `all -> Relation`

Return a `Relation` for all rows in the table.

```ruby
User.all.to_a            # => T::Array[UserRecord]
```

#### `build(...) -> Record::New`

Create a new unpersisted record with keyword arguments. Returns a `Record::New` instance (no `id`).

```ruby
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.class           # => UserRecord::New
```

### Record::New Instance Methods

#### `save!(adapter: HakumiORM.adapter) -> Record`

Persist the record via `INSERT ... RETURNING *`. Returns a fully hydrated `Record` with `id`.

```ruby
user = new_user.save!
user.id                  # => Integer (guaranteed)
```

### Relation Methods

`Relation` is a chainable, lazy query builder. Nothing hits the database until a terminal method (`to_a`, `first`, `count`, etc.) is called.

#### Chainable (return `self`)

| Method | Description |
|---|---|
| `where(expr)` | Add a WHERE condition. Multiple calls are ANDed. |
| `order(clause)` | Add ORDER BY via an `OrderClause` (e.g., `UserSchema::NAME.asc`). |
| `order_by(field, direction)` | Add ORDER BY via field + `:asc` / `:desc` symbol. |
| `limit(n)` | Set LIMIT. |
| `offset(n)` | Set OFFSET. |
| `join(clause)` | Add a JOIN clause. |

```ruby
User
  .where(UserSchema::ACTIVE.eq(true))
  .order(UserSchema::NAME.asc)
  .limit(25)
  .offset(50)
```

#### Terminal (execute the query)

| Method | Returns | Description |
|---|---|---|
| `to_a` | `T::Array[Record]` | Execute and return all matching records. |
| `first` | `T.nilable(Record)` | Execute with LIMIT 1 and return the first record. |
| `count` | `Integer` | Execute `SELECT COUNT(*)` and return the count. |
| `pluck_raw(field)` | `T::Array[T.nilable(String)]` | Return raw string values for a single column. |
| `delete_all` | `Integer` | Execute `DELETE` and return the number of deleted rows. |
| `update_all(assignments)` | `Integer` | Execute `UPDATE` and return the number of updated rows. |
| `to_sql` | `CompiledQuery` | Return the compiled SQL + binds **without executing**. |

```ruby
# Execute
users = User.all.to_a
first = User.all.order(UserSchema::NAME.asc).first

# Aggregate
total = User.where(UserSchema::ACTIVE.eq(true)).count

# Pluck raw values
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
```

### Field Predicates

Every `Schema::FIELD` constant is a typed field object. The available predicates depend on the field type.

#### All fields (`Field`)

| Method | SQL | Example |
|---|---|---|
| `eq(value)` | `= $1` | `UserSchema::NAME.eq("Alice")` |
| `neq(value)` | `!= $1` | `UserSchema::NAME.neq("Alice")` |
| `in_list(values)` | `IN ($1, $2, ...)` | `UserSchema::ID.in_list([1, 2, 3])` |
| `not_in_list(values)` | `NOT IN ($1, $2, ...)` | `UserSchema::ID.not_in_list([1, 2])` |
| `is_null` | `IS NULL` | `UserSchema::AGE.is_null` |
| `is_not_null` | `IS NOT NULL` | `UserSchema::AGE.is_not_null` |

#### Comparable fields (`IntField`, `FloatField`, `DecimalField`, `TimeField`, `DateField`)

| Method | SQL | Example |
|---|---|---|
| `gt(value)` | `> $1` | `UserSchema::AGE.gt(18)` |
| `gte(value)` | `>= $1` | `UserSchema::AGE.gte(18)` |
| `lt(value)` | `< $1` | `UserSchema::AGE.lt(65)` |
| `lte(value)` | `<= $1` | `UserSchema::AGE.lte(65)` |
| `between(low, high)` | `BETWEEN $1 AND $2` | `UserSchema::AGE.between(18, 65)` |

#### Text fields (`StrField`)

| Method | SQL | Example |
|---|---|---|
| `like(pattern)` | `LIKE $1` | `UserSchema::EMAIL.like("%@gmail.com")` |
| `ilike(pattern)` | `ILIKE $1` | `UserSchema::NAME.ilike("alice")` |

#### Ordering

| Method | Returns | Example |
|---|---|---|
| `asc` | `OrderClause` | `UserSchema::NAME.asc` |
| `desc` | `OrderClause` | `UserSchema::NAME.desc` |

### Expression Combinators

Predicates return `Expr` objects that can be combined with boolean logic:

| Method | SQL | Example |
|---|---|---|
| `expr.and(other)` | `(left) AND (right)` | `UserSchema::ACTIVE.eq(true).and(UserSchema::AGE.gt(18))` |
| `expr.or(other)` | `(left) OR (right)` | `UserSchema::NAME.eq("Alice").or(UserSchema::NAME.eq("Bob"))` |
| `expr.not` | `NOT (expr)` | `UserSchema::ACTIVE.eq(true).not` |

Expressions nest with deterministic parentheses:

```ruby
User.where(
  UserSchema::AGE.gte(18)
    .and(UserSchema::EMAIL.like("%@company.com"))
    .or(UserSchema::NAME.eq("admin"))
)
```

### Associations

Associations are generated automatically from foreign keys. No manual declaration needed.

#### `has_many` (one-to-many)

Returns a **lazy `Relation`** -- no query is executed until a terminal method is called. The relation is fully chainable.

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

#### `belongs_to` (many-to-one)

Returns the related record by executing a `find` on the foreign key value.

```ruby
post = Post.find(1)
post.user                    # => T.nilable(UserRecord) (executes SELECT)
```

#### Association loading behavior

Associations are **lazy-loaded** by default. Each call executes an independent query:

```ruby
users = User.all.to_a           # 1 query
users.each do |u|
  puts u.posts.count             # 1 query per user (N+1)
end
```

There is no `includes` / `preload` / `eager_load` yet. For batch loading, query the association table directly:

```ruby
users = User.all.to_a
user_ids = users.map(&:id)
all_posts = Post.where(PostSchema::USER_ID.in_list(user_ids)).to_a
posts_by_user = all_posts.group_by(&:user_id)
```

### Creating Records

```ruby
# Build a new (unpersisted) record
new_user = User.build(name: "Alice", email: "alice@example.com", active: true)
new_user.name    # => "Alice"
new_user.class   # => UserRecord::New (no id attribute)

# Persist it -- INSERT RETURNING * hydrates a full record
user = new_user.save!
user.class       # => UserRecord
user.id          # => Integer (guaranteed non-nil)
```

### Custom Models

Generated code lives in `app/db/generated/` and is always overwritten. Your models live in `app/models/` and are never touched after the initial stub generation:

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

### Type Casting

Raw PostgreSQL strings are converted to Ruby types through a strict `Cast` module:

```ruby
HakumiORM::Cast.integer("42")                         # => 42
HakumiORM::Cast.boolean("t")                          # => true
HakumiORM::Cast.timestamp("2024-01-15 09:30:00.123456") # => Time
HakumiORM::Cast.decimal("99999.00001")                # => BigDecimal
```

Nullable columns use `get_value` (returns `T.nilable(String)`), non-nullable columns use `fetch_value` (returns `String`, raises on unexpected NULL).

### CompiledQuery

The result of `to_sql`. Contains the raw SQL and bind parameters without executing.

| Method | Returns | Description |
|---|---|---|
| `sql` | `String` | The parameterized SQL string (e.g., `SELECT ... WHERE "age" > $1`) |
| `binds` | `T::Array[Bind]` | Array of typed bind objects |
| `pg_params` | `T::Array[PGValue]` | Array of raw values suitable for `PG::Connection#exec_params` |

## Architecture

All source code lives under `lib/hakumi_orm/`. Every file is Sorbet `typed: strict`. See [`lib/hakumi_orm/README.md`](lib/hakumi_orm/README.md) for a full reference of every module, class, and public API.

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

A `sandbox/` directory (gitignored) lets you test against a real PostgreSQL database:

```bash
createdb hakumi_sandbox
bundle exec ruby sandbox/smoke_test.rb
```

This connects to a local database, creates tables, runs the code generator, loads the generated files, and exercises the full API: all predicates, relation methods, CRUD, associations, and mutations.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Run `bin/ci` to verify all checks pass
4. Commit your changes
5. Open a Pull Request

All contributions must pass RuboCop, Sorbet (`typed: strict`), and the full test suite.

## License

Released under the [MIT License](LICENSE.txt).

<p align="center">
  <a href="https://github.com/hakumi-dev">hakumi-dev</a>
</p>
