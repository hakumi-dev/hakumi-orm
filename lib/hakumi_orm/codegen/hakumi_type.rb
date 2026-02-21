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
      end

      sig { returns(::String) }
      def ruby_type
        case self
        when Integer   then "Integer"
        when String    then "String"
        when Boolean   then "T::Boolean"
        when Timestamp then "Time"
        when Date      then "Date"
        when Float     then "Float"
        when Decimal   then "BigDecimal"
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
        when String    then "::HakumiORM::StrField"
        when Boolean   then "::HakumiORM::BoolField"
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
        self == String
      end
    end
  end
end
