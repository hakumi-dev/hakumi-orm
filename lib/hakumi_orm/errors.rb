# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Errors
    extend T::Sig

    sig { void }
    def initialize
      @messages = T.let({}, T::Hash[Symbol, T::Array[String]])
    end

    sig { params(field: Symbol, message: String).void }
    def add(field, message)
      (@messages[field] ||= []) << message
    end

    sig { returns(T::Boolean) }
    def valid?
      @messages.empty?
    end

    sig { returns(T::Hash[Symbol, T::Array[String]]) }
    attr_reader :messages

    sig { returns(T::Array[String]) }
    def full_messages
      @messages.flat_map { |field, msgs| msgs.map { |m| "#{field} #{m}" } }
    end

    sig { returns(Integer) }
    def count
      @messages.values.sum(&:length)
    end
  end
end
