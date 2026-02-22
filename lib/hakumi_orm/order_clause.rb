# typed: strict
# frozen_string_literal: true

module HakumiORM
  class OrderClause
    extend T::Sig

    sig { returns(FieldRef) }
    attr_reader :field

    sig { returns(Symbol) }
    attr_reader :direction

    sig { params(field: FieldRef, direction: Symbol).void }
    def initialize(field, direction)
      @field = T.let(field, FieldRef)
      @direction = T.let(direction, Symbol)
    end
  end
end
