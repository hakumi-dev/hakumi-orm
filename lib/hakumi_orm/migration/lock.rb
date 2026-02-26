# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    # Advisory lock lifecycle for migration runs.
    class Lock
      extend T::Sig

      sig { params(adapter: Adapter::Base).void }
      def initialize(adapter)
        @adapter = T.let(adapter, Adapter::Base)
      end

      sig { params(blk: T.proc.void).void }
      def with_advisory_lock(&blk)
        dialect = @adapter.dialect
        unless dialect.supports_advisory_lock?
          blk.call
          return
        end

        lock_sql = dialect.advisory_lock_sql
        unlock_sql = dialect.advisory_unlock_sql
        acquire_advisory_lock!(lock_sql) if lock_sql
        begin
          blk.call
        ensure
          @adapter.exec(unlock_sql).close if unlock_sql
        end
      end

      private

      sig { params(sql: String).void }
      def acquire_advisory_lock!(sql)
        result = @adapter.exec(sql)
        begin
          @adapter.dialect.verify_advisory_lock!(result)
        ensure
          result.close
        end
      end
    end
  end
end
