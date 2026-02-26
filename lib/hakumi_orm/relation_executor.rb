# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Reopens Relation with terminal read-side execution methods and result handling.
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
        table: @table_name,
        where_expr: combined_where,
        joins: @joins
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.row_count.positive? }
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
  end
end
