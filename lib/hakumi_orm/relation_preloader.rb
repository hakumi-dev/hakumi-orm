# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Coordinates preload node traversal and delegates node dispatch to a relation.
  class RelationPreloader
    extend T::Sig
    extend T::Generic

    ModelType = type_member

    sig do
      params(
        relation: Relation[ModelType],
        records: T::Array[ModelType],
        nodes: T::Array[PreloadNode],
        adapter: Adapter::Base
      ).void
    end
    def initialize(relation, records, nodes, adapter)
      @relation = T.let(relation, Relation[ModelType])
      @records = T.let(records, T::Array[ModelType])
      @nodes = T.let(nodes, T::Array[PreloadNode])
      @adapter = T.let(adapter, Adapter::Base)
    end

    sig { params(depth: Integer, max_depth: Integer).void }
    def run(depth:, max_depth:)
      raise HakumiORM::Error, "Preload depth limit (#{max_depth}) exceeded — possible circular preload" if depth > max_depth

      @nodes.each do |node|
        @relation.dispatch_preload_node(node, @records, @adapter, depth: depth)
      end
    end
  end
end
