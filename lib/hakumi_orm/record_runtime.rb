# typed: strict
# frozen_string_literal: true

module HakumiORM
  module RecordRuntime
    extend T::Sig

    module_function

    sig do
      type_parameters(:R)
        .params(
          result: ::HakumiORM::Adapter::Result,
          dialect: ::HakumiORM::Dialect::Base,
          blk: T.proc
               .params(row: T::Array[::HakumiORM::Adapter::CellValue], dialect: ::HakumiORM::Dialect::Base)
               .returns(T.type_parameter(:R))
        )
        .returns(T::Array[T.type_parameter(:R)])
    end
    def hydrate_result_rows(result, dialect, &blk)
      n = result.row_count
      return [] if n.zero?

      all_rows = result.values
      rows = T.let(::Array.new(n), T::Array[T.type_parameter(:R)])
      i = 0
      while i < n
        rows[i] = blk.call(all_rows.fetch(i), dialect)
        i += 1
      end
      rows
    end

    sig do
      type_parameters(:R)
        .params(
          result: ::HakumiORM::Adapter::Result,
          dialect: ::HakumiORM::Dialect::Base,
          blk: T.proc
               .params(row: T::Array[::HakumiORM::Adapter::CellValue], dialect: ::HakumiORM::Dialect::Base)
               .returns(T.type_parameter(:R))
        )
        .returns(T.nilable(T.type_parameter(:R)))
    end
    def hydrate_result_first(result, dialect, &blk)
      return nil if result.row_count.zero?

      row = result.values.fetch(0)
      blk.call(row, dialect)
    end

    sig do
      type_parameters(:V)
        .params(
          current: T::Hash[Symbol, T.all(T.type_parameter(:V), BasicObject)],
          other: T::Hash[Symbol, T.all(T.type_parameter(:V), BasicObject)]
        )
        .returns(T::Boolean)
    end
    def changed_hash?(current, other)
      current.each do |key, value|
        return true if value != other.fetch(key)
      end

      false
    end

    sig do
      type_parameters(:V)
        .params(
          current: T::Hash[Symbol, T.all(T.type_parameter(:V), BasicObject)],
          other: T::Hash[Symbol, T.all(T.type_parameter(:V), BasicObject)]
        )
        .returns(T::Hash[Symbol, T::Array[T.type_parameter(:V)]])
    end
    def diff_hash(current, other)
      diff = T.let({}, T::Hash[Symbol, T::Array[T.type_parameter(:V)]])
      current.each do |key, value|
        other_value = other.fetch(key)
        diff[key] = [value, other_value] if value != other_value
      end
      diff
    end

    sig { overridable.params(_row: T::Array[::HakumiORM::Adapter::CellValue], _dialect: ::HakumiORM::Dialect::Base).void }
    def _hydrate_row_values!(_row, _dialect)
      Kernel.raise NotImplementedError, "generated record must implement _hydrate_row_values!"
    end
  end
end
