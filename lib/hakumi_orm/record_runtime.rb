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
          blk: T.proc.params(h: T::Hash[Symbol, T.type_parameter(:V)]).void
        )
        .returns(T::Hash[Symbol, T.type_parameter(:V)])
    end
    def build_symbol_hash(&blk)
      h = T.let({}, T::Hash[Symbol, T.type_parameter(:V)])
      blk.call(h)
      h
    end

    sig do
      type_parameters(:V)
        .params(
          blk: T.proc.params(h: T::Hash[String, T.type_parameter(:V)]).void
        )
        .returns(T::Hash[String, T.type_parameter(:V)])
    end
    def build_string_hash(&blk)
      h = T.let({}, T::Hash[String, T.type_parameter(:V)])
      blk.call(h)
      h
    end

    sig do
      type_parameters(:V)
        .params(
          symbol_hash: T::Hash[Symbol, T.type_parameter(:V)],
          key: Symbol,
          blk: T.proc.returns(T.type_parameter(:V))
        ).void
    end
    def append_symbol_field!(symbol_hash, key:, &blk)
      symbol_hash[key] = blk.call
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

    sig do
      params(
        field: Symbol,
        only: T.nilable(T::Array[Symbol]),
        except: T.nilable(T::Array[Symbol])
      ).returns(T::Boolean)
    end
    def json_field_allowed?(field, only:, except:)
      return false if only && !only.include?(field)
      return false if except&.include?(field)

      true
    end

    sig do
      type_parameters(:V)
        .params(
          json_hash: T::Hash[String, T.type_parameter(:V)],
          field: Symbol,
          key: String,
          only: T.nilable(T::Array[Symbol]),
          except: T.nilable(T::Array[Symbol]),
          blk: T.proc.returns(T.type_parameter(:V))
        ).void
    end
    def append_json_field!(json_hash, field:, key:, only:, except:, &blk)
      return unless json_field_allowed?(field, only: only, except: except)

      json_hash[key] = blk.call
    end

    sig { overridable.params(_row: T::Array[::HakumiORM::Adapter::CellValue], _dialect: ::HakumiORM::Dialect::Base).void }
    def _hydrate_row_values!(_row, _dialect)
      Kernel.raise NotImplementedError, "generated record must implement _hydrate_row_values!"
    end
  end
end
