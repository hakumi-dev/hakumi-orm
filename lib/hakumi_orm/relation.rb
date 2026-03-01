# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Immutable fluent query object that compiles and executes ORM relations.
  class Relation
    extend T::Sig
    extend T::Helpers
    extend T::Generic

    abstract!

    ModelType = type_member
    CteEntry = T.type_alias { [String, CompiledQuery, T::Boolean] }

    class << self
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :table_name_override

      sig { params(name: T.nilable(String)).void }
      def table_name_override=(name)
        @table_name_override = T.let(name, T.nilable(String))
      end
    end

    sig { params(table_name: String, columns: T::Array[FieldRef]).void }
    def initialize(table_name, columns)
      @table_name = T.let(table_name, String)
      @columns = T.let(columns, T::Array[FieldRef])
      @from_table_name = T.let(nil, T.nilable(String))
      @select_columns = T.let(nil, T.nilable(T::Array[FieldRef]))
      @where_exprs = T.let([], T::Array[Expr])
      @default_exprs = T.let([], T::Array[Expr])
      @cte_entries = T.let([], T::Array[CteEntry])
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
      default_from = self.class.table_name_override
      @from_table_name = default_from if default_from
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where(expr)
      relation = dup
      relation.push_where_expr(expr)
      relation
    end

    sig { params(sql: String, binds: T::Array[Bind]).returns(T.self_type) }
    def where_raw(sql, binds = [])
      relation = dup
      relation.push_where_expr(RawExpr.new(sql, binds))
      relation
    end

    sig { params(clause: OrderClause).returns(T.self_type) }
    def order(clause)
      relation = dup
      relation.push_order_clause(clause)
      relation
    end

    sig { params(field: FieldRef, direction: Symbol).returns(T.self_type) }
    def order_by(field, direction = :asc)
      relation = dup
      relation.push_order_clause(OrderClause.new(field, direction))
      relation
    end

    sig { params(n: Integer).returns(T.self_type) }
    def limit(n)
      relation = dup
      relation.assign_limit(n)
      relation
    end

    sig { params(n: Integer).returns(T.self_type) }
    def offset(n)
      relation = dup
      relation.assign_offset(n)
      relation
    end

    sig { params(fields: FieldRef).returns(T.self_type) }
    def select(*fields)
      relation = dup
      relation.assign_select_columns(fields)
      relation
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def join(clause)
      relation = dup
      relation.push_join_clause(clause)
      relation
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def left_joins(clause)
      relation = dup
      relation.push_join_clause(with_join_type(clause, :left))
      relation
    end

    sig { returns(T.self_type) }
    def distinct
      relation = dup
      relation.enable_distinct
      relation
    end

    sig { params(fields: FieldRef).returns(T.self_type) }
    def group(*fields)
      relation = dup
      relation.push_group_fields(fields)
      relation
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def having(expr)
      relation = dup
      relation.push_having_expr(expr)
      relation
    end

    sig { params(clause: String).returns(T.self_type) }
    def lock(clause = "FOR UPDATE")
      relation = dup
      relation.assign_lock(clause)
      relation
    end

    sig { params(other: Relation[ModelType]).returns(T.self_type) }
    def or(other)
      left = where_expression
      right = other.where_expression
      relation = dup
      if left && right
        relation.replace_where_exprs([left.or(right)])
      elsif right
        relation.replace_where_exprs([right])
      end
      relation
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where_not(expr)
      relation = dup
      relation.push_where_expr(NotExpr.new(expr))
      relation
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def rewhere(expr)
      relation = dup
      relation.replace_where_exprs([expr])
      relation
    end

    sig { params(clauses: OrderClause).returns(T.self_type) }
    def reorder(*clauses)
      relation = dup
      relation.replace_order_clauses(clauses)
      relation
    end

    sig { params(scopes: Symbol).returns(T.self_type) }
    def unscope(*scopes)
      relation = dup
      scopes.each { |scope| relation.apply_unscope(scope) }
      relation
    end

    sig { params(table_name: String).returns(T.self_type) }
    def from(table_name)
      validate_table_name!(table_name)
      relation = dup
      relation.assign_from_table(table_name)
      relation
    end

    sig { params(name: String, subquery: CompiledQuery).returns(T.self_type) }
    def with(name, subquery)
      validate_cte_name!(name)
      relation = dup
      relation.push_cte_entry([name, subquery, false])
      relation
    end

    sig { params(name: String, subquery: CompiledQuery).returns(T.self_type) }
    def with_recursive(name, subquery)
      validate_cte_name!(name)
      relation = dup
      relation.push_cte_entry([name, subquery, true])
      relation
    end

    sig { returns(T.self_type) }
    def unscoped
      relation = dup
      relation.assign_default_exprs([])
      relation
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

    sig { params(expr: Expr).void }
    def push_where_expr(expr)
      @where_exprs << expr
    end

    sig { params(exprs: T::Array[Expr]).void }
    def replace_where_exprs(exprs)
      @where_exprs = exprs
    end

    sig { params(clause: OrderClause).void }
    def push_order_clause(clause)
      @order_clauses << clause
    end

    sig { params(clauses: T::Array[OrderClause]).void }
    def replace_order_clauses(clauses)
      @order_clauses = clauses
    end

    sig { params(clause: JoinClause).void }
    def push_join_clause(clause)
      @joins << clause
    end

    sig { params(fields: T::Array[FieldRef]).void }
    def push_group_fields(fields)
      @group_fields.concat(fields)
    end

    sig { params(expr: Expr).void }
    def push_having_expr(expr)
      @having_exprs << expr
    end

    sig { params(entry: CteEntry).void }
    def push_cte_entry(entry)
      @cte_entries << entry
    end

    sig { params(n: Integer).void }
    def assign_limit(n)
      @limit_value = n
    end

    sig { params(n: Integer).void }
    def assign_offset(n)
      @offset_value = n
    end

    sig { params(cols: T::Array[FieldRef]).void }
    def assign_select_columns(cols)
      @select_columns = cols
    end

    sig { void }
    def enable_distinct
      @distinct_value = true
    end

    sig { params(clause: String).void }
    def assign_lock(clause)
      @lock_value = clause
    end

    sig { params(name: T.nilable(String)).void }
    def assign_from_table(name)
      @from_table_name = name
    end

    sig { params(exprs: T::Array[Expr]).void }
    def assign_default_exprs(exprs)
      @default_exprs = exprs
      @defaults_pristine = false
    end

    sig { params(scope: Symbol).void }
    def apply_unscope(scope)
      case scope
      when :where then @where_exprs = []
      when :order then @order_clauses = []
      when :joins then @joins = []
      when :group then @group_fields = []
      when :having then @having_exprs = []
      when :limit then @limit_value = nil
      when :offset then @offset_value = nil
      when :lock then @lock_value = nil
      when :select then @select_columns = nil
      when :distinct then @distinct_value = false
      when :from then @from_table_name = nil
      when :with then @cte_entries = []
      else raise ArgumentError, "Unsupported unscope target: #{scope.inspect}"
      end
    end

    sig { returns(T.nilable(Expr)) }
    def where_expression = combined_where

    sig { returns(String) }
    def source_table_name
      @from_table_name || @table_name
    end

    sig { returns(T.nilable(String)) }
    def source_table_alias
      return nil if source_table_name == @table_name

      @table_name
    end

    sig { returns(T::Array[CteEntry]) }
    attr_reader :cte_entries

    private

    sig { params(source: Relation[ModelType]).void }
    def initialize_copy(source)
      super
      @where_exprs = @where_exprs.dup
      @default_exprs = @default_exprs.dup
      @cte_entries = @cte_entries.dup
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
        table_alias: source_table_alias,
        columns: columns_override || @select_columns || @columns,
        ctes: @cte_entries,
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

    sig { params(table_name: String).void }
    def validate_table_name!(table_name)
      parts = table_name.split(".")
      return if !parts.empty? && parts.all? { |part| part.match?(IDENTIFIER) }

      raise ArgumentError, "Invalid table name for from: #{table_name.inspect}"
    end

    sig { params(name: String).void }
    def validate_cte_name!(name)
      return if name.match?(IDENTIFIER)

      raise ArgumentError, "Invalid CTE name: #{name.inspect}"
    end

    IDENTIFIER = T.let(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, Regexp)
  end
end

require_relative "relation_query"
require_relative "relation_executor"
require_relative "relation_preloader"
require_relative "relation_preloading"
require_relative "relation_batches"
require_relative "relation_aggregates"
