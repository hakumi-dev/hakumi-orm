# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"

module HakumiORM
  PGValue = T.type_alias { T.nilable(T.any(Integer, Float, String, T::Boolean)) }

  class Bind
    extend T::Sig
    extend T::Helpers

    abstract!
    sealed!

    sig { abstract.returns(PGValue) }
    def pg_value; end
  end

  class IntBind < Bind
    extend T::Sig

    sig { returns(T.nilable(Integer)) }
    attr_reader :value

    sig { params(value: T.nilable(Integer)).void }
    def initialize(value)
      @value = T.let(value, T.nilable(Integer))
    end

    sig { override.returns(PGValue) }
    def pg_value
      @value
    end
  end

  class StrBind < Bind
    extend T::Sig

    sig { returns(String) }
    attr_reader :value

    sig { params(value: String).void }
    def initialize(value)
      @value = T.let(value, String)
    end

    sig { override.returns(String) }
    def pg_value
      @value
    end
  end

  class FloatBind < Bind
    extend T::Sig

    sig { returns(Float) }
    attr_reader :value

    sig { params(value: Float).void }
    def initialize(value)
      @value = T.let(value, Float)
    end

    sig { override.returns(Float) }
    def pg_value
      @value
    end
  end

  class DecimalBind < Bind
    extend T::Sig

    sig { returns(BigDecimal) }
    attr_reader :value

    sig { params(value: BigDecimal).void }
    def initialize(value)
      @value = T.let(value, BigDecimal)
    end

    sig { override.returns(String) }
    def pg_value
      @value.to_s("F")
    end
  end

  class BoolBind < Bind
    extend T::Sig

    sig { returns(T::Boolean) }
    attr_reader :value

    sig { params(value: T::Boolean).void }
    def initialize(value)
      @value = T.let(value, T::Boolean)
    end

    sig { override.returns(String) }
    def pg_value
      @value ? "t" : "f"
    end
  end

  class TimeBind < Bind
    extend T::Sig

    sig { returns(Time) }
    attr_reader :value

    sig { params(value: Time).void }
    def initialize(value)
      @value = T.let(value, Time)
    end

    sig { override.returns(String) }
    def pg_value
      @value.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
    end
  end

  class DateBind < Bind
    extend T::Sig

    sig { returns(Date) }
    attr_reader :value

    sig { params(value: Date).void }
    def initialize(value)
      @value = T.let(value, Date)
    end

    sig { override.returns(String) }
    def pg_value
      @value.iso8601
    end
  end

  class JsonBind < Bind
    extend T::Sig

    sig { returns(Json) }
    attr_reader :value

    sig { params(value: Json).void }
    def initialize(value)
      @value = T.let(value, Json)
    end

    sig { override.returns(String) }
    def pg_value
      @value.to_json
    end
  end

  class NullBind < Bind
    extend T::Sig

    sig { override.returns(NilClass) }
    def pg_value
      nil
    end
  end

  class IntArrayBind < Bind
    extend T::Sig

    sig { returns(T::Array[T.nilable(Integer)]) }
    attr_reader :value

    sig { params(value: T::Array[T.nilable(Integer)]).void }
    def initialize(value)
      @value = T.let(value, T::Array[T.nilable(Integer)])
    end

    sig { override.returns(String) }
    def pg_value
      "{#{@value.map { |v| v.nil? ? "NULL" : v.to_s }.join(",")}}"
    end
  end

  class StrArrayBind < Bind
    extend T::Sig

    sig { returns(T::Array[T.nilable(String)]) }
    attr_reader :value

    sig { params(value: T::Array[T.nilable(String)]).void }
    def initialize(value)
      @value = T.let(value, T::Array[T.nilable(String)])
    end

    sig { override.returns(String) }
    def pg_value
      inner = @value.map do |v|
        if v.nil?
          "NULL"
        else
          "\"#{v.gsub("\\", "\\\\\\\\").gsub('"', '\\"')}\""
        end
      end
      "{#{inner.join(",")}}"
    end
  end

  class FloatArrayBind < Bind
    extend T::Sig

    sig { returns(T::Array[T.nilable(Float)]) }
    attr_reader :value

    sig { params(value: T::Array[T.nilable(Float)]).void }
    def initialize(value)
      @value = T.let(value, T::Array[T.nilable(Float)])
    end

    sig { override.returns(String) }
    def pg_value
      "{#{@value.map { |v| v.nil? ? "NULL" : v.to_s }.join(",")}}"
    end
  end

  class BoolArrayBind < Bind
    extend T::Sig

    sig { returns(T::Array[T.nilable(T::Boolean)]) }
    attr_reader :value

    sig { params(value: T::Array[T.nilable(T::Boolean)]).void }
    def initialize(value)
      @value = T.let(value, T::Array[T.nilable(T::Boolean)])
    end

    sig { override.returns(String) }
    def pg_value
      inner = @value.map do |v|
        if v.nil? then "NULL"
        elsif v then "t"
        else "f"
        end
      end
      "{#{inner.join(",")}}"
    end
  end
end
