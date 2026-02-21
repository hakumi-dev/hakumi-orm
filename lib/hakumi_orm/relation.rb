# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Relation
    extend T::Sig
    extend T::Helpers
    extend T::Generic

    abstract!

    ModelType = type_member

    sig { params(table_name: String, columns: T::Array[FieldRef]).void }
    def initialize(table_name, columns)
      @table_name = T.let(table_name, String)
      @columns = T.let(columns, T::Array[FieldRef])
      @where_exprs = T.let([], T::Array[Expr])
      @order_clauses = T.let([], T::Array[OrderClause])
      @joins = T.let([], T::Array[JoinClause])
      @limit_value = T.let(nil, T.nilable(Integer))
      @offset_value = T.let(nil, T.nilable(Integer))
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where(expr)
      @where_exprs << expr
      self
    end

    sig { params(clause: OrderClause).returns(T.self_type) }
    def order(clause)
      @order_clauses << clause
      self
    end

    sig { params(field: FieldRef, direction: Symbol).returns(T.self_type) }
    def order_by(field, direction = :asc)
      @order_clauses << OrderClause.new(field, direction)
      self
    end

    sig { params(n: Integer).returns(T.self_type) }
    def limit(n)
      @limit_value = n
      self
    end

    sig { params(n: Integer).returns(T.self_type) }
    def offset(n)
      @offset_value = n
      self
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def join(clause)
      @joins << clause
      self
    end

    sig { abstract.params(result: Adapter::Result).returns(T::Array[ModelType]) }
    def hydrate(result); end

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def to_a(adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect)
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      hydrate(result)
    ensure
      result&.close
    end

    sig { params(adapter: Adapter::Base).returns(T.nilable(ModelType)) }
    def first(adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, limit_override: 1)
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      hydrate(result).first
    ensure
      result&.close
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def count(adapter: HakumiORM.adapter)
      compiled = SqlCompiler.new(adapter.dialect).count(
        table: @table_name,
        where_expr: combined_where
      )
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      T.must(result.get_value(0, 0)).to_i
    ensure
      result&.close
    end

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T::Array[T.nilable(String)]) }
    def pluck_raw(field, adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, columns_override: [field])
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      result.column_values(0)
    ensure
      result&.close
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def delete_all(adapter: HakumiORM.adapter)
      compiled = SqlCompiler.new(adapter.dialect).delete(
        table: @table_name,
        where_expr: combined_where
      )
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      result.affected_rows
    ensure
      result&.close
    end

    sig { params(assignments: T::Array[Assignment], adapter: Adapter::Base).returns(Integer) }
    def update_all(assignments, adapter: HakumiORM.adapter)
      compiled = SqlCompiler.new(adapter.dialect).update(
        table: @table_name,
        assignments: assignments,
        where_expr: combined_where
      )
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      result.affected_rows
    ensure
      result&.close
    end

    sig { params(adapter: Adapter::Base).returns(CompiledQuery) }
    def to_sql(adapter: HakumiORM.adapter)
      build_select(adapter.dialect)
    end

    private

    sig { returns(T.nilable(Expr)) }
    def combined_where
      return nil if @where_exprs.empty?

      result = T.let(T.must(@where_exprs[0]), Expr)
      i = T.let(1, Integer)
      while i < @where_exprs.length
        result = AndExpr.new(result, T.must(@where_exprs[i]))
        i += 1
      end
      result
    end

    sig do
      params(
        dialect: Dialect::Base,
        columns_override: T.nilable(T::Array[FieldRef]),
        limit_override: T.nilable(Integer)
      ).returns(CompiledQuery)
    end
    def build_select(dialect, columns_override: nil, limit_override: nil)
      SqlCompiler.new(dialect).select(
        table: @table_name,
        columns: columns_override || @columns,
        where_expr: combined_where,
        orders: @order_clauses,
        joins: @joins,
        limit_val: limit_override || @limit_value,
        offset_val: @offset_value
      )
    end
  end
end
