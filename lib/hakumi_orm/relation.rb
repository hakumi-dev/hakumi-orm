# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Mutable fluent query object that compiles and executes ORM relations.
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
      @from_table_name = T.let(nil, T.nilable(String))
      @select_columns = T.let(nil, T.nilable(T::Array[FieldRef]))
      @where_exprs = T.let([], T::Array[Expr])
      @default_exprs = T.let([], T::Array[Expr])
      @order_clauses = T.let([], T::Array[OrderClause])
      @joins = T.let([], T::Array[JoinClause])
      @limit_value = T.let(nil, T.nilable(Integer))
      @offset_value = T.let(nil, T.nilable(Integer))
      @distinct_value = T.let(false, T::Boolean)
      @lock_value = T.let(nil, T.nilable(String))
      @group_fields = T.let([], T::Array[FieldRef])
      @having_exprs = T.let([], T::Array[Expr])
      @_preloaded_results = T.let(nil, T.nilable(T::Array[ModelType]))
      @_preload_nodes = T.let([], T::Array[PreloadNode])
      @defaults_pristine = T.let(true, T::Boolean)
      @compiled_select_cache = T.let({}, T::Hash[Symbol, CompiledQuery])
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where(expr)
      @where_exprs << expr
      invalidate_compiled_cache!
      self
    end

    sig { params(sql: String, binds: T::Array[Bind]).returns(T.self_type) }
    def where_raw(sql, binds = [])
      @where_exprs << RawExpr.new(sql, binds)
      invalidate_compiled_cache!
      self
    end

    sig { params(clause: OrderClause).returns(T.self_type) }
    def order(clause)
      @order_clauses << clause
      invalidate_compiled_cache!
      self
    end

    sig { params(field: FieldRef, direction: Symbol).returns(T.self_type) }
    def order_by(field, direction = :asc)
      @order_clauses << OrderClause.new(field, direction)
      invalidate_compiled_cache!
      self
    end

    sig { params(n: Integer).returns(T.self_type) }
    def limit(n)
      @limit_value = n
      invalidate_compiled_cache!
      self
    end

    sig { params(n: Integer).returns(T.self_type) }
    def offset(n)
      @offset_value = n
      invalidate_compiled_cache!
      self
    end

    sig { params(fields: FieldRef).returns(T.self_type) }
    def select(*fields)
      @select_columns = T.let(fields, T.nilable(T::Array[FieldRef]))
      invalidate_compiled_cache!
      self
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def join(clause)
      @joins << clause
      invalidate_compiled_cache!
      self
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def left_joins(clause)
      @joins << with_join_type(clause, :left)
      invalidate_compiled_cache!
      self
    end

    sig { returns(T.self_type) }
    def distinct
      @distinct_value = true
      invalidate_compiled_cache!
      self
    end

    sig { params(fields: FieldRef).returns(T.self_type) }
    def group(*fields)
      @group_fields.concat(fields)
      invalidate_compiled_cache!
      self
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def having(expr)
      @having_exprs << expr
      invalidate_compiled_cache!
      self
    end

    sig { params(clause: String).returns(T.self_type) }
    def lock(clause = "FOR UPDATE")
      @lock_value = clause
      invalidate_compiled_cache!
      self
    end

    sig { params(other: Relation[ModelType]).returns(T.self_type) }
    def or(other)
      left = combined_where
      right = other.where_expression
      if left && right
        @where_exprs = [left.or(right)]
      elsif right
        @where_exprs = [right]
      end
      invalidate_compiled_cache!
      self
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where_not(expr)
      @where_exprs << NotExpr.new(expr)
      invalidate_compiled_cache!
      self
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def rewhere(expr)
      @where_exprs = [expr]
      invalidate_compiled_cache!
      self
    end

    sig { params(clauses: OrderClause).returns(T.self_type) }
    def reorder(*clauses)
      @order_clauses = clauses
      invalidate_compiled_cache!
      self
    end

    sig { params(scopes: Symbol).returns(T.self_type) }
    def unscope(*scopes)
      scopes.each { |scope| unscope_single!(scope) }
      invalidate_compiled_cache!
      self
    end

    sig { params(table_name: String).returns(T.self_type) }
    def from(table_name)
      validate_table_name!(table_name)
      @from_table_name = table_name
      invalidate_compiled_cache!
      self
    end

    sig { returns(T.self_type) }
    def unscoped
      @default_exprs = []
      mark_defaults_dirty!
      invalidate_compiled_cache!
      self
    end

    sig { abstract.params(result: Adapter::Result, dialect: Dialect::Base).returns(T::Array[ModelType]) }
    def hydrate(result, dialect); end

    sig { params(adapter: Adapter::Base).returns(CompiledQuery) }
    def to_sql(adapter: HakumiORM.adapter)
      compile(adapter.dialect)
    end

    sig { params(dialect: Dialect::Base).returns(CompiledQuery) }
    def compile(dialect)
      key = dialect.name
      cached = @compiled_select_cache[key]
      return cached if cached

      compiled = build_select(dialect)
      @compiled_select_cache[key] = compiled
      compiled
    end

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(record: ModelType).void).void }
    def find_each(batch_size: 1000, adapter: HakumiORM.adapter, &blk)
      reject_partial_select!
      find_in_batches(batch_size: batch_size, adapter: adapter) do |batch|
        batch.each(&blk)
      end
    end

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches(batch_size: 1000, adapter: HakumiORM.adapter, &blk)
      if adapter.dialect.supports_cursors?
        find_in_batches_cursor(batch_size, adapter, &blk)
      else
        find_in_batches_limit(batch_size, adapter, &blk)
      end
    end

    sig { overridable.returns(T.nilable(String)) }
    def stmt_count_all = nil

    sig { overridable.returns(T.nilable(String)) }
    def sql_count_all = nil

    protected

    sig { returns(T.nilable(Expr)) }
    def where_expression = combined_where

    sig { returns(String) }
    def source_table_name
      @from_table_name || @table_name
    end

    private

    IDENTIFIER = T.let(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, Regexp)

    sig { void }
    def mark_defaults_dirty!
      @defaults_pristine = false
    end

    sig { void }
    def invalidate_compiled_cache!
      @compiled_select_cache.clear
    end

    sig { params(source: Relation[ModelType]).void }
    def initialize_copy(source)
      super
      @where_exprs = @where_exprs.dup
      @default_exprs = @default_exprs.dup
      @order_clauses = @order_clauses.dup
      @joins = @joins.dup
      @group_fields = @group_fields.dup
      @having_exprs = @having_exprs.dup
      @_preload_nodes = @_preload_nodes.dup
      @from_table_name = @from_table_name&.dup
      @compiled_select_cache = {}
    end

    sig { void }
    def reject_partial_select!
      return unless @select_columns

      raise HakumiORM::Error,
            "Cannot hydrate records with a partial column set. Use pluck or pluck_raw for column subsets"
    end

    sig { returns(T.nilable(Expr)) }
    def combined_where
      return combine_exprs(@where_exprs) if @default_exprs.empty?
      return combine_exprs(@default_exprs) if @where_exprs.empty?

      combine_exprs(@default_exprs + @where_exprs)
    end

    sig { returns(T.nilable(Expr)) }
    def combined_having = combine_exprs(@having_exprs)

    sig do
      params(
        dialect: Dialect::Base,
        columns_override: T.nilable(T::Array[FieldRef]),
        limit_override: T.nilable(Integer),
        offset_override: T.nilable(Integer)
      ).returns(CompiledQuery)
    end
    def build_select(dialect, columns_override: nil, limit_override: nil, offset_override: nil)
      dialect.compiler.select(
        table: source_table_name,
        columns: columns_override || @select_columns || @columns,
        where_expr: combined_where,
        orders: @order_clauses,
        joins: @joins,
        limit_val: limit_override || @limit_value,
        offset_val: offset_override || @offset_value,
        distinct: @distinct_value,
        lock: @lock_value,
        group_fields: @group_fields,
        having_expr: combined_having
      )
    end

    sig { params(clause: JoinClause, join_type: Symbol).returns(JoinClause) }
    def with_join_type(clause, join_type)
      return clause if clause.join_type == join_type

      JoinClause.new(join_type, clause.target_table, clause.source_field, clause.target_field)
    end

    sig { params(scope: Symbol).void }
    def unscope_single!(scope)
      case scope
      when :where
        @where_exprs = []
      when :order
        @order_clauses = []
      when :joins
        @joins = []
      when :group
        @group_fields = []
      when :having
        @having_exprs = []
      when :limit
        @limit_value = nil
      when :offset
        @offset_value = nil
      when :lock
        @lock_value = nil
      when :select
        @select_columns = nil
      when :distinct
        @distinct_value = false
      when :from
        @from_table_name = nil
      else
        raise ArgumentError, "Unsupported unscope target: #{scope.inspect}"
      end
    end

    sig { params(table_name: String).void }
    def validate_table_name!(table_name)
      return if table_name.match?(IDENTIFIER)

      raise ArgumentError, "Invalid table name for from: #{table_name.inspect}"
    end
  end
end

require_relative "relation_query"
require_relative "relation_executor"
require_relative "relation_preloader"
require_relative "relation_preloading"
require_relative "relation_batches"
require_relative "relation_aggregates"
