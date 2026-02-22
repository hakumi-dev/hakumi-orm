# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    class HakumiType < T::Enum
      extend T::Sig

      enums do
        Integer = new
        String = new
        Boolean = new
        Timestamp = new
        Date = new
        Float = new
        Decimal = new
        Json = new
        Uuid = new
      end

      sig { returns(::String) }
      def ruby_type
        case self
        when Integer      then "Integer"
        when String, Uuid then "String"
        when Boolean      then "T::Boolean"
        when Timestamp    then "Time"
        when Date         then "Date"
        when Float        then "Float"
        when Decimal      then "BigDecimal"
        when Json         then "::HakumiORM::Json"
        else T.absurd(self)
        end
      end

      sig { params(nullable: T::Boolean).returns(::String) }
      def ruby_type_string(nullable:)
        base = ruby_type
        nullable ? "T.nilable(#{base})" : base
      end

      sig { returns(::String) }
      def field_class
        case self
        when Integer   then "::HakumiORM::IntField"
        when Float     then "::HakumiORM::FloatField"
        when Decimal   then "::HakumiORM::DecimalField"
        when Timestamp then "::HakumiORM::TimeField"
        when Date      then "::HakumiORM::DateField"
        when String, Uuid then "::HakumiORM::StrField"
        when Boolean      then "::HakumiORM::BoolField"
        when Json         then "::HakumiORM::JsonField"
        else T.absurd(self)
        end
      end

      sig { returns(T::Boolean) }
      def comparable?
        case self
        when Integer, Float, Decimal, Timestamp, Date then true
        else false
        end
      end

      sig { returns(T::Boolean) }
      def text?
        case self
        when String, Uuid then true
        else false
        end
      end

      sig { returns(::String) }
      def bind_class
        case self
        when Integer   then "::HakumiORM::IntBind"
        when Float     then "::HakumiORM::FloatBind"
        when Decimal   then "::HakumiORM::DecimalBind"
        when Timestamp then "::HakumiORM::TimeBind"
        when Date      then "::HakumiORM::DateBind"
        when String, Uuid then "::HakumiORM::StrBind"
        when Boolean      then "::HakumiORM::BoolBind"
        when Json         then "::HakumiORM::JsonBind"
        else T.absurd(self)
        end
      end
    end
  end
end
