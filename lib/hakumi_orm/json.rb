# typed: strict
# frozen_string_literal: true

require "json"

module HakumiORM
  JsonScalar = T.type_alias { T.nilable(T.any(String, Integer, Float, T::Boolean)) }

  class Json
    extend T::Sig

    sig { returns(String) }
    attr_reader :raw_json

    sig { params(raw_json: String).void }
    def initialize(raw_json)
      @raw_json = T.let(raw_json, String)
    end

    sig { params(raw: String).returns(Json) }
    def self.parse(raw)
      JSON.parse(raw)
      new(raw)
    end

    sig { params(hash: T::Hash[String, JsonScalar]).returns(Json) }
    def self.from_hash(hash)
      new(JSON.generate(hash))
    end

    sig { params(arr: T::Array[JsonScalar]).returns(Json) }
    def self.from_array(arr)
      new(JSON.generate(arr))
    end

    sig { params(key: String).returns(T.nilable(Json)) }
    def [](key)
      parsed = JSON.parse(@raw_json)
      return nil unless parsed.is_a?(Hash)

      val = parsed[key]
      return nil if val.nil?

      Json.new(JSON.generate(val))
    end

    sig { params(index: Integer).returns(T.nilable(Json)) }
    def at(index)
      parsed = JSON.parse(@raw_json)
      return nil unless parsed.is_a?(Array)

      val = parsed[index]
      return nil if val.nil?

      Json.new(JSON.generate(val))
    end

    sig { returns(T.nilable(String)) }
    def as_s
      parsed = JSON.parse(@raw_json)
      parsed.is_a?(String) ? parsed : nil
    end

    sig { returns(T.nilable(Integer)) }
    def as_i
      parsed = JSON.parse(@raw_json)
      parsed.is_a?(Integer) ? parsed : nil
    end

    sig { returns(T.nilable(Float)) }
    def as_f
      parsed = JSON.parse(@raw_json)
      parsed.is_a?(Float) ? parsed : nil
    end

    sig { returns(T.nilable(T::Boolean)) }
    def as_bool
      parsed = JSON.parse(@raw_json)
      return true if parsed.equal?(true)
      return false if parsed.equal?(false)

      nil
    end

    sig { returns(JsonScalar) }
    def scalar
      parsed = JSON.parse(@raw_json)
      case parsed
      when String, Integer, Float then parsed
      when TrueClass then true
      when FalseClass then false
      end
    end

    sig { params(_args: T.nilable(T.any(String, Integer, Float, T::Boolean))).returns(String) }
    def to_json(*_args)
      @raw_json
    end

    sig { returns(String) }
    def to_s
      @raw_json
    end

    sig { params(other: T.nilable(Json)).returns(T::Boolean) }
    def ==(other)
      return false if other.nil?

      JSON.parse(@raw_json) == JSON.parse(other.raw_json)
    end
  end
end
