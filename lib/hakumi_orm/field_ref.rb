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
