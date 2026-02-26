# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Relation

    private

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches_cursor(batch_size, adapter, &blk)
      dialect = adapter.dialect
      compiled = build_select(dialect)
      cursor_name = "hakumi_cursor_#{object_id}"

      adapter.transaction do |_txn|
        declare_result = adapter.exec_params("DECLARE #{cursor_name} CURSOR FOR #{compiled.sql}", compiled.params_for(dialect))
        declare_result.close
        begin
          loop do
            result = adapter.exec("FETCH #{batch_size} FROM #{cursor_name}")
            batch = hydrate(result, dialect)
            result.close
            break if batch.empty?

            blk.call(batch)
            break if batch.length < batch_size
          end
        ensure
          begin
            close_result = adapter.exec("CLOSE #{cursor_name}")
            close_result.close
          rescue StandardError
            nil
          end
        end
      end
    end

    sig { params(batch_size: Integer, adapter: Adapter::Base, blk: T.proc.params(batch: T::Array[ModelType]).void).void }
    def find_in_batches_limit(batch_size, adapter, &blk)
      dialect = adapter.dialect
      current_offset = T.let(0, Integer)
      loop do
        compiled = build_select(dialect, limit_override: batch_size, offset_override: current_offset)
        result = adapter.exec_params(compiled.sql, compiled.params_for(dialect))
        batch = hydrate(result, dialect)
        result.close
        break if batch.empty?

        blk.call(batch)
        break if batch.length < batch_size

        current_offset += batch_size
      end
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
