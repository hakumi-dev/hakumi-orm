# typed: false
# frozen_string_literal: true

# Fixtures simulating generated code for a "users" table.
# This is what the codegen would produce for:
#   CREATE TABLE users (
#     id serial PRIMARY KEY,
#     name varchar NOT NULL,
#     email varchar NOT NULL,
#     age integer,
#     active boolean NOT NULL DEFAULT true
#   );

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

  sig { params(result: HakumiORM::Adapter::Result).returns(T::Array[UserRecord]) }
  def self.from_result(result)
    n = result.row_count
    rows = T.let(::Array.new(n), T::Array[UserRecord])
    i = T.let(0, Integer)
    while i < n
      rows[i] = new(
        id: result.fetch_value(i, 0).to_i,
        name: result.fetch_value(i, 1),
        email: result.fetch_value(i, 2),
        age: result.get_value(i, 3)&.to_i,
        active: result.fetch_value(i, 4) == "t"
      )
      i += 1
    end
    rows
  end

  sig { params(name: String, email: String, active: T::Boolean, age: T.nilable(Integer)).returns(UserRecord::New) }
  def self.build(name:, email:, active:, age: nil)
    UserRecord::New.new(name: name, email: email, age: age, active: active)
  end

  sig { params(expr: HakumiORM::Expr).returns(UserRelation) }
  def self.where(expr)
    UserRelation.new.where(expr)
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

    sig { overridable.params(record: UserRecord::Checkable, e: HakumiORM::Errors).void }
    def self.on_all(record, e); end

    sig { overridable.params(record: UserRecord::New, e: HakumiORM::Errors).void }
    def self.on_create(record, e); end

    sig { overridable.params(record: UserRecord::Checkable, adapter: HakumiORM::Adapter::Base, e: HakumiORM::Errors).void }
    def self.on_persist(record, adapter, e); end
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

  sig { override.params(result: HakumiORM::Adapter::Result).returns(T::Array[UserRecord]) }
  def hydrate(result)
    UserRecord.from_result(result)
  end
end
