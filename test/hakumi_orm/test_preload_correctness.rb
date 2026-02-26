# typed: false
# frozen_string_literal: true

require "test_helper"

class PreloadUser
  attr_reader :id
  attr_accessor :posts

  def initialize(id:)
    @id = id
    @posts = []
  end
end

class PreloadPost
  attr_reader :id, :user_id, :title
  attr_accessor :comments

  def initialize(id:, user_id:, title:)
    @id = id
    @user_id = user_id
    @title = title
    @comments = []
  end
end

class PreloadComment
  attr_reader :id, :post_id, :body
  attr_accessor :replies

  def initialize(id:, post_id:, body:)
    @id = id
    @post_id = post_id
    @body = body
    @replies = []
  end
end

class PreloadReply
  attr_reader :id, :comment_id, :body

  def initialize(id:, comment_id:, body:)
    @id = id
    @comment_id = comment_id
    @body = body
  end
end

class PreloadCommentRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: PreloadComment } }

  sig { void }
  def initialize
    super("comments", [])
  end

  sig { override.params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[PreloadComment]) }
  def hydrate(result, dialect)
    _ = dialect
    result.values.map do |row|
      PreloadComment.new(id: row.fetch(0), post_id: row.fetch(1), body: row.fetch(2))
    end
  end

  sig { override.params(node: HakumiORM::PreloadNode, records: T::Array[PreloadComment], adapter: HakumiORM::Adapter::Base, depth: Integer).void }
  def dispatch_preload_node(node, records, adapter, depth: 0)
    _ = depth
    case node.name
    when :replies
      return if records.empty?

      comment_ids = records.map(&:id)
      sql = 'SELECT "replies"."id", "replies"."comment_id", "replies"."body" FROM "replies" ' \
            "WHERE \"replies\".\"comment_id\" IN (#{placeholders(comment_ids.length)}) " \
            'ORDER BY "replies"."comment_id" ASC, "replies"."id" ASC'
      result = adapter.exec_params(sql, comment_ids)
      replies = result.values.map do |row|
        PreloadReply.new(id: row.fetch(0), comment_id: row.fetch(1), body: row.fetch(2))
      end
      grouped = replies.group_by(&:comment_id)
      records.each { |comment| comment.replies = grouped.fetch(comment.id, []) }
    else
      custom_preload(node.name, records, adapter)
    end
  ensure
    result&.close
  end

  private

  sig { params(n: Integer).returns(String) }
  def placeholders(n)
    (1..n).map { |i| "$#{i}" }.join(", ")
  end
end

class PreloadPostRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: PreloadPost } }

  sig { void }
  def initialize
    super("posts", [])
  end

  sig { override.params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[PreloadPost]) }
  def hydrate(result, dialect)
    _ = dialect
    result.values.map do |row|
      PreloadPost.new(id: row.fetch(0), user_id: row.fetch(1), title: row.fetch(2))
    end
  end

  sig { override.params(node: HakumiORM::PreloadNode, records: T::Array[PreloadPost], adapter: HakumiORM::Adapter::Base, depth: Integer).void }
  def dispatch_preload_node(node, records, adapter, depth: 0)
    _ = depth
    case node.name
    when :comments
      return if records.empty?

      post_ids = records.map(&:id)
      sql = 'SELECT "comments"."id", "comments"."post_id", "comments"."body" FROM "comments" ' \
            "WHERE \"comments\".\"post_id\" IN (#{placeholders(post_ids.length)}) " \
            'ORDER BY "comments"."post_id" ASC, "comments"."id" ASC'
      result = adapter.exec_params(sql, post_ids)
      comments = PreloadCommentRelation.new.hydrate(result, adapter.dialect)
      grouped = comments.group_by(&:post_id)
      records.each { |post| post.comments = grouped.fetch(post.id, []) }

      unless node.children.empty?
        all_comments = records.flat_map(&:comments)
        PreloadCommentRelation.new.run_preloads(all_comments, node.children, adapter, depth: depth + 1)
      end
    else
      custom_preload(node.name, records, adapter)
    end
  ensure
    result&.close
  end

  private

  sig { params(n: Integer).returns(String) }
  def placeholders(n)
    (1..n).map { |i| "$#{i}" }.join(", ")
  end
end

class PreloadUserRelation < HakumiORM::Relation
  extend T::Sig

  ModelType = type_member { { fixed: PreloadUser } }

  sig { void }
  def initialize
    super("users", [])
  end

  sig { override.params(result: HakumiORM::Adapter::Result, dialect: HakumiORM::Dialect::Base).returns(T::Array[PreloadUser]) }
  def hydrate(result, dialect)
    _ = dialect
    result.values.map { |row| PreloadUser.new(id: row.fetch(0)) }
  end

  sig { override.params(node: HakumiORM::PreloadNode, records: T::Array[PreloadUser], adapter: HakumiORM::Adapter::Base, depth: Integer).void }
  def dispatch_preload_node(node, records, adapter, depth: 0)
    case node.name
    when :posts
      return if records.empty?

      user_ids = records.map(&:id)
      sql = 'SELECT "posts"."id", "posts"."user_id", "posts"."title" FROM "posts" ' \
            "WHERE \"posts\".\"user_id\" IN (#{placeholders(user_ids.length)}) " \
            'ORDER BY "posts"."user_id" ASC, "posts"."id" ASC'
      result = adapter.exec_params(sql, user_ids)
      posts = PreloadPostRelation.new.hydrate(result, adapter.dialect)
      grouped = posts.group_by(&:user_id)
      records.each { |user| user.posts = grouped.fetch(user.id, []) }

      unless node.children.empty?
        all_posts = records.flat_map(&:posts)
        PreloadPostRelation.new.run_preloads(all_posts, node.children, adapter, depth: depth + 1)
      end
    else
      custom_preload(node.name, records, adapter)
    end
  ensure
    result&.close
  end

  private

  sig { params(n: Integer).returns(String) }
  def placeholders(n)
    (1..n).map { |i| "$#{i}" }.join(", ")
  end
end

class TestPreloadCorrectness < HakumiORM::TestCase
  def setup
    @adapter = HakumiORM::Test::MockAdapter.new
  end

  test "has_many preload runs one query for all parent records (no N+1)" do
    users = [PreloadUser.new(id: 1), PreloadUser.new(id: 2), PreloadUser.new(id: 3)]
    @adapter.stub_result(
      'FROM "posts"',
      [
        [11, 1, "A"],
        [12, 1, "B"],
        [21, 2, "C"]
      ]
    )

    PreloadUserRelation.new.run_preloads(users, [HakumiORM::PreloadNode.new(:posts)], @adapter)

    assert_equal 1, @adapter.executed_queries.length
    assert_includes @adapter.executed_queries.first.fetch(:sql), 'FROM "posts"'
    assert_equal [1, 2, 3], @adapter.executed_queries.first.fetch(:params)
  end

  test "has_many preload groups children onto the correct parent and preserves row order within each group" do
    users = [PreloadUser.new(id: 1), PreloadUser.new(id: 2), PreloadUser.new(id: 3)]
    @adapter.stub_result(
      'FROM "posts"',
      [
        [11, 1, "A"],
        [12, 1, "B"],
        [21, 2, "C"]
      ]
    )

    PreloadUserRelation.new.run_preloads(users, [HakumiORM::PreloadNode.new(:posts)], @adapter)

    assert_equal [11, 12], users[0].posts.map(&:id)
    assert_equal [21], users[1].posts.map(&:id)
    assert_empty users[2].posts
  end

  test "nested has_many preloads run one query per level and group correctly" do
    users = [PreloadUser.new(id: 1), PreloadUser.new(id: 2), PreloadUser.new(id: 3)]
    @adapter.stub_result(
      'FROM "posts"',
      [
        [11, 1, "A"],
        [12, 1, "B"],
        [21, 2, "C"]
      ]
    )
    @adapter.stub_result(
      'FROM "comments"',
      [
        [101, 11, "c1"],
        [102, 11, "c2"],
        [201, 21, "c3"]
      ]
    )

    node = HakumiORM::PreloadNode.new(:posts, [HakumiORM::PreloadNode.new(:comments)])
    PreloadUserRelation.new.run_preloads(users, [node], @adapter)

    assert_equal 2, @adapter.executed_queries.length
    assert_includes @adapter.executed_queries[0].fetch(:sql), 'FROM "posts"'
    assert_includes @adapter.executed_queries[1].fetch(:sql), 'FROM "comments"'
    assert_equal [101, 102], users[0].posts[0].comments.map(&:id)
    assert_empty users[0].posts[1].comments
    assert_equal [201], users[1].posts[0].comments.map(&:id)
  end

  test "preload with empty parent records executes no query" do
    PreloadUserRelation.new.run_preloads([], [HakumiORM::PreloadNode.new(:posts)], @adapter)

    assert_empty @adapter.executed_queries
  end

  test "preload stress: high fanout groups all children onto one parent without N+1" do
    users = [PreloadUser.new(id: 1), PreloadUser.new(id: 2), PreloadUser.new(id: 3)]
    rows = (1..1000).map { |i| [i, 1, "P#{i}"] }
    rows.push([1001, 2, "P1001"], [1002, 2, "P1002"])
    @adapter.stub_result('FROM "posts"', rows)

    PreloadUserRelation.new.run_preloads(users, [HakumiORM::PreloadNode.new(:posts)], @adapter)

    assert_equal 1, @adapter.executed_queries.length
    assert_equal [1, 2, 3], @adapter.executed_queries.first.fetch(:params)
    assert_equal 1000, users[0].posts.length
    assert_equal [1, 2, 3, 4, 5], users[0].posts.first(5).map(&:id)
    assert_equal [1001, 1002], users[1].posts.map(&:id)
    assert_empty users[2].posts
    assert_equal(rows.length, users.sum { |u| u.posts.length })
  end

  test "preload stress: many parents still runs one query and keeps sparse grouping correct" do
    users = (1..200).map { |i| PreloadUser.new(id: i) }
    @adapter.stub_result(
      'FROM "posts"',
      [
        [11, 1, "A"],
        [22, 50, "B"],
        [33, 200, "C"]
      ]
    )

    PreloadUserRelation.new.run_preloads(users, [HakumiORM::PreloadNode.new(:posts)], @adapter)

    assert_equal 1, @adapter.executed_queries.length
    assert_equal 200, @adapter.executed_queries.first.fetch(:params).length
    assert_equal [11], users[0].posts.map(&:id)
    assert_empty users[1].posts
    assert_equal [22], users[49].posts.map(&:id)
    assert_equal [33], users[199].posts.map(&:id)
  end

  test "preload stress: nested depth 3 runs one query per level and groups correctly" do
    users = [PreloadUser.new(id: 1), PreloadUser.new(id: 2), PreloadUser.new(id: 3)]
    @adapter.stub_result(
      'FROM "posts"',
      [
        [11, 1, "A"],
        [12, 1, "B"],
        [21, 2, "C"]
      ]
    )
    @adapter.stub_result(
      'FROM "comments"',
      [
        [101, 11, "c1"],
        [102, 11, "c2"],
        [201, 21, "c3"]
      ]
    )
    @adapter.stub_result(
      'FROM "replies"',
      [
        [1001, 101, "r1"],
        [1002, 101, "r2"],
        [2001, 201, "r3"]
      ]
    )

    node = HakumiORM::PreloadNode.new(
      :posts,
      [HakumiORM::PreloadNode.new(:comments, [HakumiORM::PreloadNode.new(:replies)])]
    )
    PreloadUserRelation.new.run_preloads(users, [node], @adapter)

    assert_equal 3, @adapter.executed_queries.length
    assert_includes @adapter.executed_queries[0].fetch(:sql), 'FROM "posts"'
    assert_includes @adapter.executed_queries[1].fetch(:sql), 'FROM "comments"'
    assert_includes @adapter.executed_queries[2].fetch(:sql), 'FROM "replies"'

    first_comment = users[0].posts[0].comments[0]
    second_comment = users[0].posts[0].comments[1]
    third_comment = users[1].posts[0].comments[0]

    assert_equal [1001, 1002], first_comment.replies.map(&:id)
    assert_empty second_comment.replies
    assert_equal [2001], third_comment.replies.map(&:id)
  end
end
