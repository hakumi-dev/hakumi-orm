# typed: strict
# frozen_string_literal: true

module HakumiORM
  class FieldRef
    extend T::Sig

    sig { returns(Symbol) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :table_name

    sig { returns(String) }
    attr_reader :column_name

    sig { returns(String) }
    attr_reader :qualified_name

    sig { params(name: Symbol, table_name: String, column_name: String, qualified_name: String).void }
    def initialize(name, table_name, column_name, qualified_name)
      @name = T.let(name, Symbol)
      @table_name = T.let(table_name, String)
      @column_name = T.let(column_name, String)
      @qualified_name = T.let(qualified_name, String)
    end

    sig { returns(OrderClause) }
    def asc
      OrderClause.new(self, :asc)
    end

    sig { returns(OrderClause) }
    def desc
      OrderClause.new(self, :desc)
    end
  end
end
