# typed: strict
# frozen_string_literal: true

require "bigdecimal"
require "date"

module HakumiORM
  PGValue = T.type_alias { T.nilable(T.any(Integer, Float, String, T::Boolean)) }

  # Base value wrapper used to bind typed parameters to SQL statements.
  class Bind
    extend T::Sig
    extend T::Helpers

    abstract!
    sealed!

    sig { abstract.returns(PGValue) }
    def pg_value; end
  end

  # Nullable integer bind.
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

  # String bind.
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

  # Float bind.
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

  # Decimal bind serialized as fixed-point string.
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

  # Boolean bind normalized to PostgreSQL boolean literals.
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

  # Time bind normalized to UTC with microseconds.
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

  # Date bind serialized as ISO-8601.
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

  # JSON bind serialized through JSON encoding.
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

  # Explicit null bind.
  class NullBind < Bind
    extend T::Sig

    sig { override.returns(NilClass) }
    def pg_value
      nil
    end
  end

  # Integer array bind for PostgreSQL array literals.
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

  # String array bind for PostgreSQL array literals.
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
          quote_pg_array_string(v)
        end
      end
      "{#{inner.join(",")}}"
    end

    private

    sig { params(value: String).returns(String) }
    def quote_pg_array_string(value)
      escaped = +""
      value.each_char do |ch|
        escaped << "\\" if ch == "\\" || ch == '"'
        escaped << ch
      end
      "\"#{escaped}\""
    end
  end

  # Float array bind for PostgreSQL array literals.
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

  # Boolean array bind for PostgreSQL array literals.
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
