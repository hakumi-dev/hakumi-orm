# typed: strict
# frozen_string_literal: true

module HakumiORM
  PreloadSpec = T.type_alias { T.any(Symbol, T::Hash[Symbol, T.any(Symbol, T::Array[Symbol])]) }

  class PreloadNode
    extend T::Sig

    sig { returns(Symbol) }
    attr_reader :name

    sig { returns(T::Array[PreloadNode]) }
    attr_reader :children

    sig { params(name: Symbol, children: T::Array[PreloadNode]).void }
    def initialize(name, children = [])
      @name = T.let(name, Symbol)
      @children = T.let(children, T::Array[PreloadNode])
    end

    sig { params(specs: T::Array[PreloadSpec]).returns(T::Array[PreloadNode]) }
    def self.from_specs(specs)
      specs.map do |spec|
        case spec
        when Symbol
          new(spec)
        else
          spec.map do |parent, nested|
            child_nodes = case nested
                          when Symbol then [new(nested)]
                          else nested.map { |s| new(s) }
                          end
            new(parent, child_nodes)
          end
        end
      end.flatten
    end
  end
end
