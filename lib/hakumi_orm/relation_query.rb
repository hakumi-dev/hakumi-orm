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

    sig { params(fields: FieldRef, adapter: Adapter::Base).returns(T::Array[T::Array[T.nilable(String)]]) }
    def pluck(*fields, adapter: HakumiORM.adapter)
      compiled = build_select(adapter.dialect, columns_override: fields)
      use_result(adapter.exec_params(compiled.sql, compiled.pg_params)) do |r|
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
      use_result(adapter.exec_params(compiled.sql, compiled.pg_params)) { |r| r.fetch_value(0, 0) }
    end

    sig { params(result: Adapter::Result, num_cols: Integer).returns(T::Array[T::Array[T.nilable(String)]]) }
    def build_pluck_rows(result, num_cols)
      n = result.row_count
      rows = T.let(::Array.new(n), T::Array[T::Array[T.nilable(String)]])
      row_idx = 0
      while row_idx < n
        row = T.let(::Array.new(num_cols), T::Array[T.nilable(String)])
        col_idx = 0
        while col_idx < num_cols
          row[col_idx] = result.get_value(row_idx, col_idx)
          col_idx += 1
        end
        rows[row_idx] = row
        row_idx += 1
      end
      rows
    end

    sig { params(exprs: T::Array[Expr]).returns(T.nilable(Expr)) }
    def combine_exprs(exprs)
      return nil if exprs.empty?

      result = T.let(exprs.fetch(0), Expr)
      i = T.let(1, Integer)
      while i < exprs.length
        result = AndExpr.new(result, exprs.fetch(i))
        i += 1
      end
      result
    end
  end
end
