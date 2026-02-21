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
      @order_clauses = T.let([], T::Array[OrderClause])
      @joins = T.let([], T::Array[JoinClause])
      @limit_value = T.let(nil, T.nilable(Integer))
      @offset_value = T.let(nil, T.nilable(Integer))
      @_preloaded_results = T.let(nil, T.nilable(T::Array[ModelType]))
      @_preload_names = T.let(nil, T.nilable(T::Array[Symbol]))
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

    sig { params(names: Symbol).returns(T.self_type) }
    def preload(*names)
      existing = @_preload_names
      if existing
        existing.concat(names)
      else
        @_preload_names = T.let(names, T.nilable(T::Array[Symbol]))
      end
      self
    end

    sig { params(results: T::Array[ModelType]).returns(T.self_type) }
    def _set_preloaded(results)
      @_preloaded_results = results
      self
    end

    sig { abstract.params(result: Adapter::Result).returns(T::Array[ModelType]) }
    def hydrate(result); end

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def to_a(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return preloaded if preloaded

      records = fetch_records(adapter)
      names = @_preload_names
      run_preloads(records, names, adapter) if names
      records
    end

    sig { params(adapter: Adapter::Base).returns(T.nilable(ModelType)) }
    def first(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return preloaded.first if preloaded

      compiled = build_select(adapter.dialect, limit_override: 1)
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      hydrate(result).first
    ensure
      result&.close
    end

    sig { params(adapter: Adapter::Base).returns(Integer) }
    def count(adapter: HakumiORM.adapter)
      preloaded = @_preloaded_results
      return preloaded.length if preloaded

      if @where_exprs.empty? && self.class.const_defined?(:STMT_COUNT_ALL)
        stmt = T.unsafe(self.class).const_get(:STMT_COUNT_ALL)
        sql = T.unsafe(self.class).const_get(:SQL_COUNT_ALL)
        adapter.prepare(stmt, sql)
        result = adapter.exec_prepared(stmt, [])
      else
        compiled = adapter.dialect.compiler.count(
          table: @table_name,
          where_expr: combined_where
        )
        result = adapter.exec_params(compiled.sql, compiled.pg_params)
      end
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
      compiled = adapter.dialect.compiler.delete(
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
      compiled = adapter.dialect.compiler.update(
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

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(record: ModelType).void).void }
    def find_each(batch_size: 1000, adapter: HakumiORM.adapter, &blk)
      find_in_batches(batch_size: batch_size, adapter: adapter) do |batch|
        batch.each(&blk)
      end
    end

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches(batch_size: 1000, adapter: HakumiORM.adapter, &blk)
      compiled = build_select(adapter.dialect)
      cursor_name = "hakumi_cursor_#{object_id}"

      adapter.exec("BEGIN")
      declare_sql = "DECLARE #{cursor_name} CURSOR FOR #{compiled.sql}"
      adapter.exec_params(declare_sql, compiled.pg_params)

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

    sig { overridable.params(records: T::Array[ModelType], names: T::Array[Symbol], adapter: Adapter::Base).void }
    def run_preloads(records, names, adapter); end

    private

    sig { params(adapter: Adapter::Base).returns(T::Array[ModelType]) }
    def fetch_records(adapter)
      compiled = build_select(adapter.dialect)
      result = adapter.exec_params(compiled.sql, compiled.pg_params)
      hydrate(result)
    ensure
      result&.close
    end

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
      dialect.compiler.select(
        table: @table_name,
        columns: columns_override || @select_columns || @columns,
        where_expr: combined_where,
        orders: @order_clauses,
        joins: @joins,
        limit_val: limit_override || @limit_value,
        offset_val: @offset_value
      )
    end
  end
end
