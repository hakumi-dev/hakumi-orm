# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Assignment
    extend T::Sig

    sig { returns(FieldRef) }
    attr_reader :field

    sig { returns(Bind) }
    attr_reader :bind

    sig { params(field: FieldRef, bind: Bind).void }
    def initialize(field, bind)
      @field = T.let(field, FieldRef)
      @bind = T.let(bind, Bind)
    end
  end
end
