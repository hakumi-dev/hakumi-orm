# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Reopens Relation with terminal execution methods and shared result handling.
  class Relation
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

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T::Array[Adapter::CellValue]) }
    def pluck_raw(field, adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, columns_override: [field])
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.column_values(0) }
    end

    sig { params(adapter: Adapter::Base).returns(T::Boolean) }
    def exists?(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return !preloaded.empty? if preloaded

      compiled = adapter.dialect.compiler.exists(
        table: source_table_name,
        table_alias: source_table_alias,
        ctes: cte_entries,
        where_expr: combined_where,
        joins: @joins
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.row_count.positive? }
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
        table: source_table_name,
        table_alias: source_table_alias,
        ctes: cte_entries,
        where_expr: combined_where,
        joins: @joins
      )
      result = adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))
      use_result(result) { |r| r.fetch_value(0, 0).to_i }
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def delete_all(adapter: HakumiORM.adapter)
      perform_physical_delete_all(adapter)
    end

    # Always performs a physical DELETE even when subclasses override delete_all.
    sig { params(adapter: Adapter::Base).returns(Integer) }
    def really_delete_all(adapter: HakumiORM.adapter)
      perform_physical_delete_all(adapter)
    end

    sig { params(assignments: T::Array[Assignment], adapter: Adapter::Base).returns(Integer) }
    def update_all(assignments, adapter: HakumiORM.adapter)
      compiled = adapter.dialect.compiler.update(
        table: source_table_name,
        table_alias: source_table_alias,
        ctes: cte_entries,
        assignments: assignments,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
    end

    private

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

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def fetch_records(adapter)
      dialect = adapter.dialect
      compiled = build_select(dialect)
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(dialect))) { |r| hydrate(r, dialect) }
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

      @where_exprs.empty? && @joins.empty? && @defaults_pristine && source_table_name == @table_name
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def perform_physical_delete_all(adapter)
      compiled = adapter.dialect.compiler.delete(
        table: source_table_name,
        table_alias: source_table_alias,
        ctes: cte_entries,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect)), &:affected_rows)
    end
  end
end
