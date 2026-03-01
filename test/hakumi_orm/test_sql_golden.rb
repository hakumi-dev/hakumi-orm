# typed: false
# frozen_string_literal: true

require "test_helper"

class TestSqlGolden < HakumiORM::TestCase
  DialectCase = Struct.new(:dialect, :compiler, :quote, :m1, :m2, :m3, :m4, keyword_init: true)

  def setup
    @dialects = {
      postgresql: build_case(HakumiORM::Dialect::Postgresql.new),
      mysql: build_case(HakumiORM::Dialect::Mysql.new),
      sqlite: build_case(HakumiORM::Dialect::Sqlite.new)
    }

    @users_id = int_field(:id, "users")
    @users_age = int_field(:age, "users")
    @users_name = str_field(:name, "users")
    @users_active = bool_field(:active, "users")
    @users_team_id = int_field(:team_id, "users")
    @teams_id = int_field(:id, "teams")
    @teams_name = str_field(:name, "teams")
  end

  USERS = :users
  TEAMS = :teams
  ID = :id
  AGE = :age
  NAME = :name
  ACTIVE = :active
  TEAM_ID = :team_id

  test "golden select with join group having order and limit compiles exactly per dialect" do
    joins = [
      HakumiORM::JoinClause.new(:inner, "teams", @users_team_id, @teams_id)
    ]
    where_expr = @users_active.eq(true).and(@users_age.gt(18))
    having_expr = HakumiORM::RawExpr.new("COUNT(*) > ?", [HakumiORM::IntBind.new(2)])

    @dialects.each_value do |dialect_case|
      q = dialect_case.compiler.select(
        table: "users",
        columns: [@users_id, @teams_name],
        where_expr: where_expr,
        joins: joins,
        group_fields: [@users_id, @teams_name],
        having_expr: having_expr,
        orders: [@teams_name.asc, @users_id.desc],
        limit_val: 20
      )

      assert_equal expected_join_group_having_sql(dialect_case), q.sql
      assert_equal 3, q.binds.length
    end
  end

  test "golden precedence SQL differs for grouped expressions" do
    expr_a = @users_age.gt(18).and(@users_name.eq("Alice").or(@users_name.eq("Bob")))
    expr_b = @users_age.gt(18).and(@users_name.eq("Alice")).or(@users_name.eq("Bob"))

    @dialects.each_value do |dialect_case|
      sql_a = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: expr_a).sql
      sql_b = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: expr_b).sql

      refute_equal sql_a, sql_b
      assert_equal expected_precedence_sql_a(dialect_case), sql_a
      assert_equal expected_precedence_sql_b(dialect_case), sql_b
    end
  end

  test "golden distinct join query compiles exactly per dialect" do
    joins = [
      HakumiORM::JoinClause.new(:left, "teams", @users_team_id, @teams_id)
    ]
    where_expr = @teams_name.ilike("%forge%").or(@users_active.eq(true))

    @dialects.each_value do |dialect_case|
      q = dialect_case.compiler.select(
        table: "users",
        columns: [@users_name],
        distinct: true,
        joins: joins,
        where_expr: where_expr,
        orders: [@users_name.asc],
        limit_val: 10,
        offset_val: 5
      )

      assert_equal expected_distinct_join_sql(dialect_case), q.sql
      assert_equal 2, q.binds.length
    end
  end

  test "eq nil and neq nil normalize to IS NULL and IS NOT NULL" do
    @dialects.each_value do |dialect_case|
      q_eq = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.eq(nil))
      q_neq = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.neq(nil))

      assert_equal %(SELECT #{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}id#{dialect_case.quote} FROM #{dialect_case.quote}users#{dialect_case.quote} WHERE #{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}age#{dialect_case.quote} IS NULL), q_eq.sql
      assert_equal %(SELECT #{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}id#{dialect_case.quote} FROM #{dialect_case.quote}users#{dialect_case.quote} WHERE #{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}age#{dialect_case.quote} IS NOT NULL), q_neq.sql
      assert_empty q_eq.binds
      assert_empty q_neq.binds
    end
  end

  test "IN and NOT IN with empty lists keep normalized raw semantics" do
    @dialects.each_value do |dialect_case|
      q_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.in_list([]))
      q_not_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.not_in_list([]))

      assert_includes q_in.sql, "WHERE 1 = 0"
      assert_includes q_not_in.sql, "WHERE 1 = 1"
      assert_empty q_in.binds
      assert_empty q_not_in.binds
    end
  end

  test "IN and NOT IN with nil-only lists normalize to NULL predicates" do
    @dialects.each_value do |dialect_case|
      q_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.in_list([nil]))
      q_not_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.not_in_list([nil]))

      assert_includes q_in.sql, %(#{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}age#{dialect_case.quote} IS NULL)
      assert_includes q_not_in.sql, %(#{dialect_case.quote}users#{dialect_case.quote}.#{dialect_case.quote}age#{dialect_case.quote} IS NOT NULL)
      assert_empty q_in.binds
      assert_empty q_not_in.binds
    end
  end

  test "IN and NOT IN with mixed nil lists split NULL semantics from value binds" do
    @dialects.each_value do |dialect_case|
      q_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.in_list([18, nil, 21]))
      q_not_in = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: @users_age.not_in_list([18, nil, 21]))

      assert_includes q_in.sql, " OR "
      assert_includes q_in.sql, " IS NULL"
      assert_includes q_not_in.sql, " AND "
      assert_includes q_not_in.sql, " IS NOT NULL"
      assert_equal [18, 21], q_in.db_params
      assert_equal [18, 21], q_not_in.db_params
    end
  end

  test "golden COALESCE raw expr preserves placeholder replacement outside SQL literals" do
    raw = HakumiORM::RawExpr.new(
      "COALESCE(?, \"fallback?\", '?') = ?",
      [HakumiORM::IntBind.new(1), HakumiORM::IntBind.new(2)]
    )

    q_pg = @dialects.fetch(:postgresql).compiler.select(table: "users", columns: [@users_id], where_expr: raw)
    q_qm = @dialects.fetch(:mysql).compiler.select(table: "users", columns: [@users_id], where_expr: raw)

    assert_includes q_pg.sql, 'COALESCE($1, "fallback?", \'?\') = $2'
    assert_includes q_qm.sql, 'COALESCE(?, "fallback?", \'?\') = ?'
  end

  test "golden subquery IN and NOT IN SQL rebases bind markers correctly" do
    @dialects.each_value do |dialect_case|
      subquery = dialect_case.compiler.select(
        table: "teams",
        columns: [@teams_id],
        where_expr: @teams_name.eq("Core").or(@teams_name.eq("Platform"))
      )
      combined = @users_active.eq(true).and(HakumiORM::SubqueryExpr.new(@users_team_id, :in, subquery))
      q = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: combined)

      assert_equal expected_subquery_in_sql(dialect_case), q.sql
      assert_equal 3, q.binds.length

      not_in_expr = HakumiORM::SubqueryExpr.new(@users_team_id, :not_in, subquery)
      q_not = dialect_case.compiler.select(table: "users", columns: [@users_id], where_expr: not_in_expr)

      assert_equal expected_subquery_not_in_sql(dialect_case), q_not.sql
      assert_equal 2, q_not.binds.length
    end
  end

  private

  def build_case(dialect)
    HakumiORM::SqlCompiler.new(dialect).then do |compiler|
      DialectCase.new(
        dialect: dialect,
        compiler: compiler,
        quote: quote_char(dialect),
        m1: dialect.bind_marker(0),
        m2: dialect.bind_marker(1),
        m3: dialect.bind_marker(2),
        m4: dialect.bind_marker(3)
      )
    end
  end

  def quote_char(dialect)
    dialect.is_a?(HakumiORM::Dialect::Mysql) ? "`" : '"'
  end

  def int_field(name, table)
    HakumiORM::IntField.new(name, table, name.to_s, "")
  end

  def str_field(name, table)
    HakumiORM::StrField.new(name, table, name.to_s, "")
  end

  def bool_field(name, table)
    HakumiORM::BoolField.new(name, table, name.to_s, "")
  end

  def q(dialect_case, table_name, column_name)
    %(#{dialect_case.quote}#{table_name}#{dialect_case.quote}.#{dialect_case.quote}#{column_name}#{dialect_case.quote})
  end

  def expected_join_group_having_sql(dialect_case)
    "SELECT #{q(dialect_case, USERS, ID)}, #{q(dialect_case, TEAMS, NAME)} " \
      "FROM #{dialect_case.quote}users#{dialect_case.quote} INNER JOIN #{dialect_case.quote}teams#{dialect_case.quote} " \
      "ON #{q(dialect_case, USERS, TEAM_ID)} = #{q(dialect_case, TEAMS, ID)} " \
      "WHERE (#{q(dialect_case, USERS, ACTIVE)} = #{dialect_case.m1} AND #{q(dialect_case, USERS, AGE)} > #{dialect_case.m2}) " \
      "GROUP BY #{q(dialect_case, USERS, ID)}, #{q(dialect_case, TEAMS, NAME)} " \
      "HAVING COUNT(*) > #{dialect_case.m3} " \
      "ORDER BY #{q(dialect_case, TEAMS, NAME)} ASC, #{q(dialect_case, USERS, ID)} DESC " \
      "LIMIT 20"
  end

  def expected_precedence_sql_a(dialect_case)
    "SELECT #{q(dialect_case, USERS, ID)} FROM #{dialect_case.quote}users#{dialect_case.quote} " \
      "WHERE (#{q(dialect_case, USERS, AGE)} > #{dialect_case.m1} AND " \
      "(#{q(dialect_case, USERS, NAME)} = #{dialect_case.m2} OR #{q(dialect_case, USERS, NAME)} = #{dialect_case.m3}))"
  end

  def expected_precedence_sql_b(dialect_case)
    "SELECT #{q(dialect_case, USERS, ID)} FROM #{dialect_case.quote}users#{dialect_case.quote} " \
      "WHERE ((#{q(dialect_case, USERS, AGE)} > #{dialect_case.m1} AND #{q(dialect_case, USERS, NAME)} = #{dialect_case.m2}) " \
      "OR #{q(dialect_case, USERS, NAME)} = #{dialect_case.m3})"
  end

  def expected_distinct_join_sql(dialect_case)
    "SELECT DISTINCT #{q(dialect_case, USERS, NAME)} " \
      "FROM #{dialect_case.quote}users#{dialect_case.quote} LEFT JOIN #{dialect_case.quote}teams#{dialect_case.quote} " \
      "ON #{q(dialect_case, USERS, TEAM_ID)} = #{q(dialect_case, TEAMS, ID)} " \
      "WHERE (#{q(dialect_case, TEAMS, NAME)} ILIKE #{dialect_case.m1} OR #{q(dialect_case, USERS, ACTIVE)} = #{dialect_case.m2}) " \
      "ORDER BY #{q(dialect_case, USERS, NAME)} ASC LIMIT 10 OFFSET 5"
  end

  def expected_subquery_in_sql(dialect_case)
    "SELECT #{q(dialect_case, USERS, ID)} FROM #{dialect_case.quote}users#{dialect_case.quote} " \
      "WHERE (#{q(dialect_case, USERS, ACTIVE)} = #{dialect_case.m1} AND " \
      "#{q(dialect_case, USERS, TEAM_ID)} IN (SELECT #{q(dialect_case, TEAMS, ID)} FROM #{dialect_case.quote}teams#{dialect_case.quote} " \
      "WHERE (#{q(dialect_case, TEAMS, NAME)} = #{dialect_case.m2} OR #{q(dialect_case, TEAMS, NAME)} = #{dialect_case.m3})))"
  end

  def expected_subquery_not_in_sql(dialect_case)
    "SELECT #{q(dialect_case, USERS, ID)} FROM #{dialect_case.quote}users#{dialect_case.quote} " \
      "WHERE #{q(dialect_case, USERS, TEAM_ID)} NOT IN (SELECT #{q(dialect_case, TEAMS, ID)} FROM #{dialect_case.quote}teams#{dialect_case.quote} " \
      "WHERE (#{q(dialect_case, TEAMS, NAME)} = #{dialect_case.m1} OR #{q(dialect_case, TEAMS, NAME)} = #{dialect_case.m2}))"
  end
end
