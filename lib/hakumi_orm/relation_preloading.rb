# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Reopens Relation with preload declaration and preload runtime hooks.
  class Relation
    MAX_PRELOAD_DEPTH = 8

    sig { params(specs: PreloadSpec).returns(T.self_type) }
    def preload(*specs)
      @_preload_nodes.concat(PreloadNode.from_specs(specs))
      self
    end

    sig { params(results: T::Array[ModelType]).returns(T.self_type) }
    def _set_preloaded(results)
      @_preloaded_results = results
      self
    end

    sig { overridable.params(_records: T::Array[ModelType], _nodes: T::Array[PreloadNode], _adapter: Adapter::Base, depth: Integer).void }
    def run_preloads(_records, _nodes, _adapter, depth: 0)
      raise HakumiORM::Error, "Preload depth limit (#{MAX_PRELOAD_DEPTH}) exceeded — possible circular preload" if depth > MAX_PRELOAD_DEPTH
    end

    sig { overridable.params(name: Symbol, records: T::Array[ModelType], adapter: Adapter::Base).void }
    def custom_preload(name, records, adapter); end
  end
end
