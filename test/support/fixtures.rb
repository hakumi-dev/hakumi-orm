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
  class New
    extend T::Sig

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :email

    sig { returns(T.nilable(Integer)) }
    attr_reader :age

    sig { returns(T::Boolean) }
    attr_reader :active

    sig { params(name: String, email: String, active: T::Boolean, age: T.nilable(Integer)).void }
    def initialize(name:, email:, active:, age: nil)
      @name = T.let(name, String)
      @email = T.let(email, String)
      @age = T.let(age, T.nilable(Integer))
      @active = T.let(active, T::Boolean)
    end
  end
end

class UserRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: UserRecord } }

  sig { void }
  def initialize
    super(UserSchema::TABLE_NAME, UserSchema::ALL)
  end

  sig { override.params(result: HakumiORM::Adapter::Result).returns(T::Array[UserRecord]) }
  def hydrate(result)
    UserRecord.from_result(result)
  end
end
