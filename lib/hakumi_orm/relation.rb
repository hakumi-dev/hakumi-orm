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
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where(expr)
      @where_exprs << expr
      self
    end

    sig { params(sql: String, binds: T::Array[Bind]).returns(T.self_type) }
    def where_raw(sql, binds = [])
      @where_exprs << RawExpr.new(sql, binds)
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

    sig { params(fields: FieldRef).returns(T.self_type) }
    def select(*fields)
      @select_columns = T.let(fields, T.nilable(T::Array[FieldRef]))
      self
    end

    sig { params(clause: JoinClause).returns(T.self_type) }
    def join(clause)
      @joins << clause
      self
    end

    sig { params(specs: PreloadSpec).returns(T.self_type) }
    def preload(*specs)
      @_preload_nodes.concat(PreloadNode.from_specs(specs))
      self
    end

    sig { returns(T.self_type) }
    def distinct
      @distinct_value = true
      self
    end

    sig { params(fields: FieldRef).returns(T.self_type) }
    def group(*fields)
      @group_fields.concat(fields)
      self
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def having(expr)
      @having_exprs << expr
      self
    end

    sig { params(clause: String).returns(T.self_type) }
    def lock(clause = "FOR UPDATE")
      @lock_value = clause
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
      self
    end

    sig { params(expr: Expr).returns(T.self_type) }
    def where_not(expr)
      @where_exprs << NotExpr.new(expr)
      self
    end

    sig { returns(T.self_type) }
    def unscoped
      @default_exprs = []
      mark_defaults_dirty!
      self
    end

    sig { params(results: T::Array[ModelType]).returns(T.self_type) }
    def _set_preloaded(results)
      @_preloaded_results = results
      self
    end

    sig { abstract.params(result: Adapter::Result, dialect: Dialect::Base).returns(T::Array[ModelType]) }
    def hydrate(result, dialect); end

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def to_a(adapter: HakumiORM.adapter)
      reject_partial_select!
      preloaded = @_preloaded_results
      return preloaded if preloaded

      records = fetch_records(adapter)
      run_preloads(records, @_preload_nodes, adapter) unless @_preload_nodes.empty?
      records
    end

    sig { params(adapter: Adapter::Base).returns(T.nilable(ModelType)) }
    def first(adapter: HakumiORM.adapter)
      reject_partial_select!
      preloaded = @_preloaded_results
      return preloaded.first if preloaded

      dialect = adapter.dialect
      compiled = build_select(dialect, limit_override: 1)
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(dialect))) { |r| hydrate(r, dialect).first }
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def count(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return preloaded.length if preloaded

      reject_count_with_grouping!

      if can_use_prepared_count_all?(adapter)
        stmt = stmt_count_all
        sql = sql_count_all
        return use_result(adapter.prepare_exec(stmt, sql, [])) { |r| r.fetch_value(0, 0).to_i } if stmt && sql
      end

      compiled = adapter.dialect.compiler.count(
        table: @table_name,
        where_expr: combined_where,
        joins: @joins
      )
      result = adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))
      use_result(result) { |r| r.fetch_value(0, 0).to_i }
    end

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T::Array[Adapter::CellValue]) }
    def pluck_raw(field, adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, columns_override: [field])
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.column_values(0) }
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def delete_all(adapter: HakumiORM.adapter)
      compiled = adapter.dialect.compiler.delete(
        table: @table_name,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def really_delete_all(adapter: HakumiORM.adapter)
      compiled = adapter.dialect.compiler.delete(
        table: @table_name,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
    end

    sig { params(assignments: T::Array[Assignment], adapter: Adapter::Base).returns(Integer) }
    def update_all(assignments, adapter: HakumiORM.adapter)
      compiled = adapter.dialect.compiler.update(
        table: @table_name,
        assignments: assignments,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
    end

    sig { params(adapter: Adapter::Base).returns(T::Boolean) }
    def exists?(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return !preloaded.empty? if preloaded

      compiled = adapter.dialect.compiler.exists(
        table: @table_name,
        where_expr: combined_where,
        joins: @joins
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.row_count.positive? }
    end

    sig { params(adapter: Adapter::Base).returns(CompiledQuery) }
    def to_sql(adapter: HakumiORM.adapter)
      build_select(adapter.dialect)
    end

    sig { params(dialect: Dialect::Base).returns(CompiledQuery) }
    def compile(dialect)
      build_select(dialect)
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

    MAX_PRELOAD_DEPTH = 8

    sig { overridable.params(_records: T::Array[ModelType], _nodes: T::Array[PreloadNode], _adapter: Adapter::Base, depth: Integer).void }
    def run_preloads(_records, _nodes, _adapter, depth: 0)
      raise HakumiORM::Error, "Preload depth limit (#{MAX_PRELOAD_DEPTH}) exceeded — possible circular preload" if depth > MAX_PRELOAD_DEPTH
    end

    sig { overridable.params(name: Symbol, records: T::Array[ModelType], adapter: Adapter::Base).void }
    def custom_preload(name, records, adapter); end

    protected

    sig { returns(T.nilable(Expr)) }
    def where_expression = combined_where

    private

    sig { void }
    def mark_defaults_dirty!
      @defaults_pristine = false
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
    end

    sig do
      type_parameters(:R)
        .params(result: Adapter::Result, blk: T.proc.params(arg0: Adapter::Result).returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def use_result(result, &blk)
      blk.call(result)
    ensure
      result.close
    end

    sig { void }
    def reject_count_with_grouping!
      return if @group_fields.empty? && @having_exprs.empty? && !@distinct_value

      raise HakumiORM::Error,
            "count with group/having/distinct is ambiguous. " \
            "Use to_a.length or a custom aggregate query instead"
    end

    sig { params(adapter: Adapter::Base).returns(T::Boolean) }
    def can_use_prepared_count_all?(adapter)
      return false unless adapter.dialect.is_a?(Dialect::Postgresql)

      @where_exprs.empty? && @joins.empty? && @defaults_pristine
    end

    sig { void }
    def reject_partial_select!
      return unless @select_columns

      raise HakumiORM::Error,
            "Cannot hydrate records with a partial column set. Use pluck or pluck_raw for column subsets"
    end

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def fetch_records(adapter)
      dialect = adapter.dialect
      compiled = build_select(dialect)
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(dialect))) { |r| hydrate(r, dialect) }
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
        table: @table_name,
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
  end
end

require_relative "relation_query"
require_relative "relation_batches"
require_relative "relation_aggregates"
