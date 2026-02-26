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

    sig { overridable.params(records: T::Array[ModelType], nodes: T::Array[PreloadNode], adapter: Adapter::Base, depth: Integer).void }
    def run_preloads(records, nodes, adapter, depth: 0)
      RelationPreloader.new(self, records, nodes, adapter).run(depth: depth, max_depth: MAX_PRELOAD_DEPTH)
    end

    sig { overridable.params(name: Symbol, records: T::Array[ModelType], adapter: Adapter::Base).void }
    def custom_preload(name, records, adapter); end

    sig { overridable.params(node: PreloadNode, records: T::Array[ModelType], adapter: Adapter::Base, depth: Integer).void }
    def dispatch_preload_node(node, records, adapter, depth: 0)
      _ = depth
      custom_preload(node.name, records, adapter)
    end
  end
end
