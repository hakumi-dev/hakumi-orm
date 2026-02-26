# typed: false
# frozen_string_literal: true

require "test_helper"

class TestSqlSecurity < HakumiORM::TestCase
  DialectCase = Struct.new(:name, :dialect, :compiler, :marker1, :marker2, keyword_init: true)

  def setup
    @dialects = [
      build_case(:postgresql, HakumiORM::Dialect::Postgresql.new),
      build_case(:mysql, HakumiORM::Dialect::Mysql.new),
      build_case(:sqlite, HakumiORM::Dialect::Sqlite.new)
    ]
  end

  test "user-controlled values are always emitted as bind markers across dialects" do
    payload_name = "Robert'); DROP TABLE users;--"
    payload_email = "x' OR 1=1 --"

    @dialects.each do |dialect_case|
      users_name = HakumiORM::StrField.new(:name, "users", "name", "")
      users_email = HakumiORM::StrField.new(:email, "users", "email", "")
      users_id = HakumiORM::IntField.new(:id, "users", "id", "")
      expr = users_name.eq(payload_name).and(users_email.eq(payload_email))

      q = dialect_case.compiler.select(table: "users", columns: [users_id], where_expr: expr)

      refute_includes q.sql, "DROP TABLE", "payload leaked into SQL for #{dialect_case.name}"
      refute_includes q.sql, "OR 1=1", "payload leaked into SQL for #{dialect_case.name}"
      assert_includes q.sql, dialect_case.marker1
      assert_includes q.sql, dialect_case.marker2
      assert_equal [payload_name, payload_email], q.pg_params
    end
  end

  test "raw expr payloads still require placeholder binds and do not rewrite placeholders inside literals/comments" do
    raw = HakumiORM::RawExpr.new(
      "msg = '?' AND note = ? /* ? in comment */ AND tag = ?",
      [HakumiORM::StrBind.new("safe"), HakumiORM::StrBind.new("x")]
    )
    events_id = HakumiORM::IntField.new(:id, "events", "id", "")

    @dialects.each do |dialect_case|
      q = dialect_case.compiler.select(table: "events", columns: [events_id], where_expr: raw)

      assert_includes q.sql, "msg = '?'"
      assert_includes q.sql, "/* ? in comment */"
      assert_equal 2, q.binds.length
      assert_equal %w[safe x], q.pg_params
    end
  end

  test "compiler quotes reserved and weird identifiers safely across dialects" do
    table_name = "order-items"
    col_name = "select"
    join_table = "user profile"
    join_col = "group"

    field_main = HakumiORM::StrField.new(:select, table_name, col_name, "")
    field_id = HakumiORM::IntField.new(:id, table_name, "id", "")
    field_join_fk = HakumiORM::IntField.new(:user_profile_id, table_name, "user_profile_id", "")
    field_join_id = HakumiORM::IntField.new(:id, join_table, "id", "")
    field_join_group = HakumiORM::StrField.new(:group, join_table, join_col, "")
    join = HakumiORM::JoinClause.new(:left, join_table, field_join_fk, field_join_id)

    @dialects.each do |dialect_case|
      q = dialect_case.compiler.select(
        table: table_name,
        columns: [field_id, field_main, field_join_group],
        joins: [join],
        where_expr: field_main.eq("value")
      )

      assert_quoted_identifier_sql!(dialect_case, q.sql, table_name, col_name, join_table, join_col)
      refute_includes q.sql, " FROM #{table_name} "
      refute_includes q.sql, " JOIN #{join_table} "
    end
  end

  private

  def build_case(name, dialect)
    DialectCase.new(
      name: name,
      dialect: dialect,
      compiler: HakumiORM::SqlCompiler.new(dialect),
      marker1: dialect.bind_marker(0),
      marker2: dialect.bind_marker(1)
    )
  end

  def assert_quoted_identifier_sql!(dialect_case, sql, table_name, col_name, join_table, join_col)
    quoted_table = dialect_case.dialect.quote_id(table_name)
    quoted_col = dialect_case.dialect.quote_id(col_name)
    quoted_join_table = dialect_case.dialect.quote_id(join_table)
    quoted_join_col = dialect_case.dialect.quote_id(join_col)

    assert_includes sql, "#{quoted_table}.#{quoted_col}"
    assert_includes sql, "FROM #{quoted_table}"
    assert_includes sql, "JOIN #{quoted_join_table}"
    assert_includes sql, "#{quoted_join_table}.#{quoted_join_col}"
  end
end
