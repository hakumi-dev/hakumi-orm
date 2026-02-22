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

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches_cursor(batch_size, adapter, &blk)
      compiled = build_select(adapter.dialect)
      cursor_name = "hakumi_cursor_#{object_id}"

      adapter.exec("BEGIN")
      adapter.exec_params("DECLARE #{cursor_name} CURSOR FOR #{compiled.sql}", compiled.pg_params)

      loop do
        result = adapter.exec("FETCH #{batch_size} FROM #{cursor_name}")
        batch = hydrate(result)
        result.close
        break if batch.empty?

        blk.call(batch)
        break if batch.length < batch_size
      end
    ensure
      adapter.exec("CLOSE #{cursor_name}") rescue nil # rubocop:disable Style/RescueModifier
      adapter.exec("COMMIT") rescue nil # rubocop:disable Style/RescueModifier
    end

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches_limit(batch_size, adapter, &blk)
      current_offset = T.let(0, Integer)
      loop do
        compiled = build_select(adapter.dialect, limit_override: batch_size, offset_override: current_offset)
        result = adapter.exec_params(compiled.sql, compiled.pg_params)
        batch = hydrate(result)
        result.close
        break if batch.empty?

        blk.call(batch)
        break if batch.length < batch_size

        current_offset += batch_size
      end
    end

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
