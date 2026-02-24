# typed: false
# frozen_string_literal: true

class TestStatusEnum < T::Enum
  enums do
    DRAFT = new("draft")
    PUBLISHED = new("published")
    ARCHIVED = new("archived")
  end
end

module UserSchema
  ID = HakumiORM::IntField.new(:id, "users", "id", '"users"."id"').freeze
  NAME = HakumiORM::StrField.new(:name, "users", "name", '"users"."name"').freeze
  EMAIL = HakumiORM::StrField.new(:email, "users", "email", '"users"."email"').freeze
  AGE = HakumiORM::IntField.new(:age, "users", "age", '"users"."age"').freeze
  ACTIVE = HakumiORM::BoolField.new(:active, "users", "active", '"users"."active"').freeze

  ALL = [ID, NAME, EMAIL, AGE, ACTIVE].freeze
  TABLE_NAME = "users"
end

class UserRecord
  extend T::Sig

  sig { returns(Integer) }
  attr_reader :id

  sig { returns(String) }
  attr_reader :name

  sig { returns(String) }
  attr_reader :email

  sig { returns(T.nilable(Integer)) }
  attr_reader :age

  sig { returns(T::Boolean) }
  attr_reader :active

  sig { params(id: Integer, name: String, email: String, age: T.nilable(Integer), active: T::Boolean).void }
  def initialize(id:, name:, email:, age:, active:)
    @id = T.let(id, Integer)
    @name = T.let(name, String)
    @email = T.let(email, String)
    @age = T.let(age, T.nilable(Integer))
    @active = T.let(active, T::Boolean)
  end

  sig { params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[UserRecord]) }
  def self.from_result(result, dialect: HakumiORM.adapter.dialect)
    n = result.row_count
    rows = T.let(::Array.new(n), T::Array[UserRecord])
    i = T.let(0, Integer)
    while i < n
      rows[i] = new(
        id: dialect.cast_integer(result.fetch_value(i, 0)),
        name: dialect.cast_string(result.fetch_value(i, 1)),
        email: dialect.cast_string(result.fetch_value(i, 2)),
        age: ((hv = result.get_value(i, 3)).nil? ? nil : dialect.cast_integer(hv)),
        active: dialect.cast_boolean(result.fetch_value(i, 4))
      )
      i += 1
    end
    rows
  end

  sig { params(pk_value: Integer, adapter: HakumiORM::Adapter::Base).returns(T.nilable(UserRecord)) }
  def self.find(pk_value, adapter: HakumiORM.adapter)
    result = adapter.exec_params(
      'SELECT "users"."id", "users"."name", "users"."email", "users"."age", "users"."active" FROM "users" WHERE "users"."id" = $1 LIMIT 1',
      [pk_value]
    )
    return nil if result.row_count.zero?

    from_result(result, dialect: adapter.dialect).first
  ensure
    result&.close
  end

  sig { params(name: String, email: String, active: T::Boolean, age: T.nilable(Integer)).returns(UserRecord::New) }
  def self.build(name:, email:, active:, age: nil)
    UserRecord::New.new(name: name, email: email, age: age, active: active)
  end

  SQL_DELETE_BY_PK = T.let('DELETE FROM "users" WHERE "users"."id" = $1', String)

  sig { params(adapter: HakumiORM::Adapter::Base).void }
  def delete!(adapter: HakumiORM.adapter)
    errors = HakumiORM::Errors.new
    UserRecord::Contract.on_destroy(self, errors)
    raise HakumiORM::ValidationError, errors unless errors.valid?

    result = adapter.exec_params(SQL_DELETE_BY_PK, [@id])
    raise HakumiORM::Error, "DELETE affected 0 rows" if result.affected_rows.zero?

    UserRecord::Contract.after_destroy(self, adapter)
  ensure
    result&.close
  end

  sig { params(adapter: HakumiORM::Adapter::Base).returns(UserRecord) }
  def reload!(adapter: HakumiORM.adapter)
    record = self.class.find(@id, adapter: adapter)
    raise HakumiORM::Error, "Record not found on reload" unless record

    record
  end

  sig do
    params(
      name: String, email: String, age: T.nilable(Integer), active: T::Boolean,
      adapter: HakumiORM::Adapter::Base
    ).returns(UserRecord)
  end
  def update!(name: @name, email: @email, age: @age, active: @active, adapter: HakumiORM.adapter)
    proxy = UserRecord::New.new(name: name, email: email, age: age, active: active)
    errors = HakumiORM::Errors.new
    UserRecord::Contract.on_all(proxy, errors)
    UserRecord::Contract.on_update(proxy, errors)
    UserRecord::Contract.on_persist(proxy, adapter, errors)
    raise HakumiORM::ValidationError, errors unless errors.valid?

    pairs = update_dirty_pairs(name, email, age, active, adapter)
    return self if pairs.empty?

    exec_update(pairs, adapter)
  end

  sig do
    params(name: String, email: String, age: T.nilable(Integer), active: T::Boolean,
           adapter: HakumiORM::Adapter::Base).returns(T::Array[[String, HakumiORM::PGValue]])
  end
  def update_dirty_pairs(name, email, age, active, adapter)
    pairs = []
    pairs << ['"name" = $', adapter.encode(HakumiORM::StrBind.new(name))] if name != @name
    pairs << ['"email" = $', adapter.encode(HakumiORM::StrBind.new(email))] if email != @email
    pairs << ['"age" = $', age.nil? ? nil : adapter.encode(HakumiORM::IntBind.new(age))] if age != @age
    pairs << ['"active" = $', adapter.encode(HakumiORM::BoolBind.new(active))] if active != @active
    pairs
  end

  sig { params(pairs: T::Array[[String, HakumiORM::PGValue]], adapter: HakumiORM::Adapter::Base).returns(UserRecord) }
  def exec_update(pairs, adapter)
    sets = pairs.each_with_index.map { |(col, _), i| "#{col}#{i + 1}" }.join(", ")
    binds = pairs.map(&:last)
    binds << @id
    sql = %(UPDATE "users" SET #{sets} WHERE "users"."id" = $#{binds.size} RETURNING "id", "name", "email", "age", "active")
    result = adapter.exec_params(sql, binds)
    record = UserRecord.from_result(result, dialect: adapter.dialect).first
    raise HakumiORM::Error, "UPDATE returned no rows" unless record

    UserRecord::Contract.after_update(record, adapter)
    record
  ensure
    result&.close
  end

  sig { returns(T::Hash[Symbol, T.any(Integer, String, T.nilable(Integer), T::Boolean)]) }
  def to_h
    {
      id: @id,
      name: @name,
      email: @email,
      age: @age,
      active: @active
    }
  end

  sig { params(other: UserRecord).returns(T::Boolean) }
  def changed_from?(other)
    @id != other.id || @name != other.name || @email != other.email || @age != other.age || @active != other.active
  end

  sig { params(other: UserRecord).returns(T::Hash[Symbol, T::Array[T.any(Integer, String, T.nilable(Integer), T::Boolean)]]) }
  def diff(other)
    h = T.let({}, T::Hash[Symbol, T::Array[T.any(Integer, String, T.nilable(Integer), T::Boolean)]])
    h[:id] = [@id, other.id] if @id != other.id
    h[:name] = [@name, other.name] if @name != other.name
    h[:email] = [@email, other.email] if @email != other.email
    h[:age] = [@age, other.age] if @age != other.age
    h[:active] = [@active, other.active] if @active != other.active
    h
  end

  sig { params(only: T.nilable(T::Array[Symbol]), except: T.nilable(T::Array[Symbol])).returns(T::Hash[String, T.nilable(T.any(String, Integer, T::Boolean))]) }
  def as_json(only: nil, except: nil)
    h = T.let({}, T::Hash[String, T.nilable(T.any(String, Integer, T::Boolean))])
    h["id"] = @id unless (only && !only.include?(:id)) || except&.include?(:id)
    h["name"] = @name unless (only && !only.include?(:name)) || except&.include?(:name)
    h["email"] = @email unless (only && !only.include?(:email)) || except&.include?(:email)
    h["age"] = @age unless (only && !only.include?(:age)) || except&.include?(:age)
    h["active"] = @active unless (only && !only.include?(:active)) || except&.include?(:active)
    h
  end

  sig { params(expr: HakumiORM::Expr).returns(UserRelation) }
  def self.where(expr)
    UserRelation.new.where(expr)
  end

  sig { params(expr: HakumiORM::Expr, adapter: HakumiORM::Adapter::Base).returns(T.nilable(UserRecord)) }
  def self.find_by(expr, adapter: HakumiORM.adapter)
    UserRelation.new.where(expr).first(adapter: adapter)
  end

  sig { params(expr: HakumiORM::Expr, adapter: HakumiORM::Adapter::Base).returns(T::Boolean) }
  def self.exists?(expr, adapter: HakumiORM.adapter)
    UserRelation.new.where(expr).exists?(adapter: adapter)
  end

  sig { returns(UserRelation) }
  def self.all
    UserRelation.new
  end
end

class UserRecord
  module Checkable
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(String) }
    def email; end

    sig { abstract.returns(T::Boolean) }
    def active; end

    sig { abstract.returns(T.nilable(Integer)) }
    def age; end
  end
end

class UserRecord
  class BaseContract
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { overridable.params(_record: UserRecord::Checkable, _e: HakumiORM::Errors).void }
    def self.on_all(_record, _e); end

    sig { overridable.params(_record: UserRecord::New, _e: HakumiORM::Errors).void }
    def self.on_create(_record, _e); end

    sig { overridable.params(_record: UserRecord::Checkable, _e: HakumiORM::Errors).void }
    def self.on_update(_record, _e); end

    sig { overridable.params(_record: UserRecord::Checkable, _adapter: HakumiORM::Adapter::Base, _e: HakumiORM::Errors).void }
    def self.on_persist(_record, _adapter, _e); end

    sig { overridable.params(_record: UserRecord, _e: HakumiORM::Errors).void }
    def self.on_destroy(_record, _e); end

    sig { overridable.params(_record: UserRecord, _adapter: HakumiORM::Adapter::Base).void }
    def self.after_create(_record, _adapter); end

    sig { overridable.params(_record: UserRecord, _adapter: HakumiORM::Adapter::Base).void }
    def self.after_update(_record, _adapter); end

    sig { overridable.params(_record: UserRecord, _adapter: HakumiORM::Adapter::Base).void }
    def self.after_destroy(_record, _adapter); end
  end

  class Contract < BaseContract
    extend T::Sig
  end
end

class UserRecord
  class New
    extend T::Sig
    include UserRecord::Checkable

    sig { override.returns(String) }
    attr_reader :name

    sig { override.returns(String) }
    attr_reader :email

    sig { override.returns(T.nilable(Integer)) }
    attr_reader :age

    sig { override.returns(T::Boolean) }
    attr_reader :active

    sig { params(name: String, email: String, active: T::Boolean, age: T.nilable(Integer)).void }
    def initialize(name:, email:, active:, age: nil)
      @name = T.let(name, String)
      @email = T.let(email, String)
      @age = T.let(age, T.nilable(Integer))
      @active = T.let(active, T::Boolean)
    end

    sig { returns(UserRecord::Validated) }
    def validate!
      errors = HakumiORM::Errors.new
      UserRecord::Contract.on_all(self, errors)
      UserRecord::Contract.on_create(self, errors)
      raise HakumiORM::ValidationError, errors unless errors.valid?

      UserRecord::Validated.new(self)
    end
  end
end

class UserRecord
  class Validated
    extend T::Sig
    include UserRecord::Checkable

    sig { override.returns(String) }
    def name = @record.name

    sig { override.returns(String) }
    def email = @record.email

    sig { override.returns(T::Boolean) }
    def active = @record.active

    sig { override.returns(T.nilable(Integer)) }
    def age = @record.age

    sig { params(record: UserRecord::New).void }
    def initialize(record)
      record.freeze
      @record = T.let(record, UserRecord::New)
    end

    SQL_INSERT = T.let(
      'INSERT INTO "users" ("name", "email", "age", "active") VALUES ($1, $2, $3, $4) RETURNING "id", "name", "email", "age", "active"',
      String
    )

    sig { params(adapter: HakumiORM::Adapter::Base).returns(UserRecord) }
    def save!(adapter: HakumiORM.adapter)
      errors = HakumiORM::Errors.new
      UserRecord::Contract.on_all(self, errors)
      UserRecord::Contract.on_persist(self, adapter, errors)
      raise HakumiORM::ValidationError, errors unless errors.valid?

      result = adapter.exec_params(SQL_INSERT, [name, email, age, adapter.encode(HakumiORM::BoolBind.new(active))])
      record = UserRecord.from_result(result, dialect: adapter.dialect).first
      raise HakumiORM::Error, "INSERT returned no rows" unless record

      UserRecord::Contract.after_create(record, adapter)
      record
    ensure
      result&.close
    end
  end
end

class UserRecord
  class VariantBase
    extend T::Sig

    sig { returns(Integer) }
    def id = @record.id

    sig { returns(String) }
    def name = @record.name

    sig { returns(String) }
    def email = @record.email

    sig { returns(T.nilable(Integer)) }
    def age = @record.age

    sig { returns(T::Boolean) }
    def active = @record.active

    sig { params(record: UserRecord).void }
    def initialize(record:)
      @record = T.let(record, UserRecord)
    end

    sig { returns(T::Hash[Symbol, T.any(Integer, String, T.nilable(Integer), T::Boolean)]) }
    def to_h = @record.to_h

    sig { params(only: T.nilable(T::Array[Symbol]), except: T.nilable(T::Array[Symbol])).returns(T::Hash[String, T.nilable(T.any(String, Integer, T::Boolean))]) }
    def as_json(only: nil, except: nil) = @record.as_json(only: only, except: except)

    protected

    sig { returns(UserRecord) }
    attr_reader :record
  end
end

# Example user-defined variant: narrows `age` from T.nilable(Integer) to Integer
class UserRecord
  class WithAge < VariantBase
    extend T::Sig

    sig { returns(Integer) }
    attr_reader :age

    sig { params(record: UserRecord, age: Integer).void }
    def initialize(record:, age:)
      super(record: record)
      @age = T.let(age, Integer)
    end
  end
end

class UserRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: UserRecord } }

  sig { override.returns(T.nilable(String)) }
  def stmt_count_all = "hakumi_users_count"

  sig { override.returns(T.nilable(String)) }
  def sql_count_all = 'SELECT COUNT(*) FROM "users"'

  sig { void }
  def initialize
    super(UserSchema::TABLE_NAME, UserSchema::ALL)
  end

  sig { override.params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[UserRecord]) }
  def hydrate(result, dialect)
    UserRecord.from_result(result, dialect: dialect)
  end

  sig { override.params(records: T::Array[UserRecord], nodes: T::Array[HakumiORM::PreloadNode], adapter: HakumiORM::Adapter::Base, depth: Integer).void }
  def run_preloads(records, nodes, adapter, depth: 0)
    raise HakumiORM::Error, "Preload depth limit (#{MAX_PRELOAD_DEPTH}) exceeded — possible circular preload" if depth > MAX_PRELOAD_DEPTH

    nodes.each { |node| custom_preload(node.name, records, adapter) }
  end

  sig { returns(T.self_type) }
  def active = where(UserSchema::ACTIVE.eq(true))

  sig { params(min_age: Integer).returns(T.self_type) }
  def older_than(min_age) = where(UserSchema::AGE.gte(min_age))
end

module ArticleSchema
  ID = HakumiORM::IntField.new(:id, "articles", "id", '"articles"."id"').freeze
  TITLE = HakumiORM::StrField.new(:title, "articles", "title", '"articles"."title"').freeze
  DELETED_AT = HakumiORM::TimeField.new(:deleted_at, "articles", "deleted_at", '"articles"."deleted_at"').freeze

  ALL = [ID, TITLE, DELETED_AT].freeze
  TABLE_NAME = "articles"
end

class ArticleRecord
  extend T::Sig

  sig { returns(Integer) }
  attr_reader :id

  sig { returns(String) }
  attr_reader :title

  sig { returns(T.nilable(Time)) }
  attr_reader :deleted_at

  sig { params(id: Integer, title: String, deleted_at: T.nilable(Time)).void }
  def initialize(id:, title:, deleted_at: nil)
    @id = T.let(id, Integer)
    @title = T.let(title, String)
    @deleted_at = T.let(deleted_at, T.nilable(Time))
  end

  sig { params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[ArticleRecord]) }
  def self.from_result(result, dialect: HakumiORM.adapter.dialect)
    n = result.row_count
    rows = T.let(::Array.new(n), T::Array[ArticleRecord])
    i = T.let(0, Integer)
    while i < n
      rows[i] = new(
        id: dialect.cast_integer(result.fetch_value(i, 0)),
        title: dialect.cast_string(result.fetch_value(i, 1)),
        deleted_at: ((hv = result.get_value(i, 2)).nil? ? nil : dialect.cast_time(hv))
      )
      i += 1
    end
    rows
  end

  sig { returns(T::Boolean) }
  def deleted? = !@deleted_at.nil?
end

class ArticleRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: ArticleRecord } }

  sig { override.returns(T.nilable(String)) }
  def stmt_count_all = "hakumi_articles_count"

  sig { override.returns(T.nilable(String)) }
  def sql_count_all = 'SELECT COUNT(*) FROM "articles" WHERE "articles"."deleted_at" IS NULL'

  sig { void }
  def initialize
    super(ArticleSchema::TABLE_NAME, ArticleSchema::ALL)
    @default_exprs << ArticleSchema::DELETED_AT.is_null
  end

  sig { returns(T.self_type) }
  def with_deleted
    @default_exprs = []
    mark_defaults_dirty!
    self
  end

  sig { returns(T.self_type) }
  def only_deleted
    @default_exprs = [ArticleSchema::DELETED_AT.is_not_null]
    mark_defaults_dirty!
    self
  end

  sig { override.params(adapter: HakumiORM::Adapter::Base).returns(Integer) }
  def delete_all(adapter: HakumiORM.adapter)
    compiled = adapter.dialect.compiler.update(
      table: @table_name,
      assignments: [HakumiORM::Assignment.new(ArticleSchema::DELETED_AT, HakumiORM::TimeBind.new(Time.now.utc))],
      where_expr: combined_where
    )
    use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
  end

  sig { override.params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[ArticleRecord]) }
  def hydrate(result, dialect)
    ArticleRecord.from_result(result, dialect: dialect)
  end
end
