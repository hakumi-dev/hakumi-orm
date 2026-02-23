# typed: strict

module Mysql2
  class Client
    sig { returns(Integer) }
    def affected_rows; end

    sig { returns(Integer) }
    def last_id; end

    sig { params(sql: String).returns(Mysql2::Statement) }
    def prepare(sql); end

    sig { params(sql: String, options: T.untyped).returns(T.nilable(Mysql2::Result)) }
    def query(sql, options = nil); end
  end

  class Statement
    sig { params(args: T.untyped, kwargs: T.untyped).returns(T.nilable(Mysql2::Result)) }
    def execute(*args, **kwargs); end

    sig { returns(Integer) }
    def affected_rows; end

    sig { void }
    def close; end

    sig { returns(Integer) }
    def last_id; end
  end
end
