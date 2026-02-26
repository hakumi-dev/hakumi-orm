# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Relation
    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T.nilable(String)) }
    def sum(field, adapter: HakumiORM.adapter)
      run_aggregate("SUM", field, adapter)
    end

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T.nilable(String)) }
    def average(field, adapter: HakumiORM.adapter)
      run_aggregate("AVG", field, adapter)
    end

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T.nilable(String)) }
    def minimum(field, adapter: HakumiORM.adapter)
      run_aggregate("MIN", field, adapter)
    end

    sig { params(field: FieldRef, adapter: Adapter::Base).returns(T.nilable(String)) }
    def maximum(field, adapter: HakumiORM.adapter)
      run_aggregate("MAX", field, adapter)
    end

    sig { params(fields: FieldRef, adapter: Adapter::Base).returns(T::Array[T::Array[Adapter::CellValue]]) }
    def pluck(*fields, adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, columns_override: fields)
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) do |r|
        build_pluck_rows(r, fields.length)
      end
    end

    private

    sig { params(func: String, field: FieldRef, adapter: Adapter::Base).returns(T.nilable(String)) }
    def run_aggregate(func, field, adapter)
      compiled = adapter.dialect.compiler.aggregate(
        table: @table_name,
        function: func,
        field: field,
        where_expr: combined_where
      )
      use_result(adapter.exec_params(compiled.sql, compiled.params_for(adapter.dialect))) { |r| r.fetch_value(0, 0) }
    end

    sig { params(result: Adapter::Result, num_cols: Integer).returns(T::Array[T::Array[Adapter::CellValue]]) }
    def build_pluck_rows(result, num_cols)
      if num_cols == 1
        result.column_values(0).zip
      else
        result.values
      end
    end
  end
end
