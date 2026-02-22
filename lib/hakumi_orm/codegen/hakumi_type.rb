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
        IntegerArray = new
        StringArray = new
        FloatArray = new
        BooleanArray = new
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
        when IntegerArray then "T::Array[T.nilable(Integer)]"
        when StringArray  then "T::Array[T.nilable(String)]"
        when FloatArray   then "T::Array[T.nilable(Float)]"
        when BooleanArray then "T::Array[T.nilable(T::Boolean)]"
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
        when Integer      then "::HakumiORM::IntField"
        when Float        then "::HakumiORM::FloatField"
        when Decimal      then "::HakumiORM::DecimalField"
        when Timestamp    then "::HakumiORM::TimeField"
        when Date         then "::HakumiORM::DateField"
        when String, Uuid then "::HakumiORM::StrField"
        when Boolean      then "::HakumiORM::BoolField"
        when Json         then "::HakumiORM::JsonField"
        when IntegerArray then "::HakumiORM::IntArrayField"
        when StringArray  then "::HakumiORM::StrArrayField"
        when FloatArray   then "::HakumiORM::FloatArrayField"
        when BooleanArray then "::HakumiORM::BoolArrayField"
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

      sig { returns(T::Boolean) }
      def array_type?
        case self
        when IntegerArray, StringArray, FloatArray, BooleanArray then true
        else false
        end
      end

      sig { params(ivar: ::String, nullable: T::Boolean).returns(::String) }
      def as_json_expr(ivar, nullable:)
        case self
        when Integer, Float, String, Boolean, Uuid,
             IntegerArray, StringArray, FloatArray, BooleanArray
          ivar
        when Decimal
          nullable ? "#{ivar}&.to_s(\"F\")" : "#{ivar}.to_s(\"F\")"
        when Timestamp
          nullable ? "#{ivar}&.iso8601(6)" : "#{ivar}.iso8601(6)"
        when Date
          nullable ? "#{ivar}&.iso8601" : "#{ivar}.iso8601"
        when Json
          nullable ? "#{ivar}&.raw_json" : "#{ivar}.raw_json"
        else T.absurd(self)
        end
      end

      sig { returns(::String) }
      def bind_class
        case self
        when Integer      then "::HakumiORM::IntBind"
        when Float        then "::HakumiORM::FloatBind"
        when Decimal      then "::HakumiORM::DecimalBind"
        when Timestamp    then "::HakumiORM::TimeBind"
        when Date         then "::HakumiORM::DateBind"
        when String, Uuid then "::HakumiORM::StrBind"
        when Boolean      then "::HakumiORM::BoolBind"
        when Json         then "::HakumiORM::JsonBind"
        when IntegerArray then "::HakumiORM::IntArrayBind"
        when StringArray  then "::HakumiORM::StrArrayBind"
        when FloatArray   then "::HakumiORM::FloatArrayBind"
        when BooleanArray then "::HakumiORM::BoolArrayBind"
        else T.absurd(self)
        end
      end

      sig { returns(Symbol) }
      def compat_category
        case self
        when String, Uuid              then :string_like
        when Integer                   then :int_like
        when Float, Decimal            then :float_like
        when Boolean                   then :bool_like
        when Timestamp, Date           then :time_like
        when Json                      then :json_like
        when IntegerArray, StringArray,
             FloatArray, BooleanArray then :array_like
        else T.absurd(self)
        end
      end

      sig { params(other: HakumiType).returns(T::Boolean) }
      def compatible_with?(other)
        self == other || compat_category == other.compat_category
      end
    end
  end
end
