# typed: strict
# frozen_string_literal: true

module HakumiORM
  class JoinClause
    extend T::Sig

    sig { returns(Symbol) }
    attr_reader :join_type

    sig { returns(String) }
    attr_reader :target_table

    sig { returns(FieldRef) }
    attr_reader :source_field

    sig { returns(FieldRef) }
    attr_reader :target_field

    sig { params(join_type: Symbol, target_table: String, source_field: FieldRef, target_field: FieldRef).void }
    def initialize(join_type, target_table, source_field, target_field)
      @join_type = T.let(join_type, Symbol)
      @target_table = T.let(target_table, String)
      @source_field = T.let(source_field, FieldRef)
      @target_field = T.let(target_field, FieldRef)
    end
  end
end
