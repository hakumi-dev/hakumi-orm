# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    # Stores validation errors in a Rails-like shape: messages and details.
    class Errors
      extend T::Sig

      Detail = T.type_alias { T::Hash[Symbol, String] }

      sig { void }
      def initialize
        @messages = T.let({}, T::Hash[Symbol, T::Array[String]])
        @details = T.let({}, T::Hash[Symbol, T::Array[Detail]])
      end

      sig { params(field: Symbol, message: String, type: Symbol).void }
      def add(field, message, type: :invalid)
        (@messages[field] ||= []) << message
        (@details[field] ||= []) << { error: type.to_s }
      end

      sig { params(field: Symbol).returns(T::Array[String]) }
      def [](field)
        @messages.fetch(field, [])
      end

      sig { returns(T::Hash[Symbol, T::Array[String]]) }
      attr_reader :messages

      sig { returns(T::Hash[Symbol, T::Array[Detail]]) }
      attr_reader :details

      sig { returns(T::Boolean) }
      def valid?
        @messages.empty?
      end

      sig { returns(T::Boolean) }
      def empty?
        @messages.empty?
      end

      sig { returns(T::Boolean) }
      def invalid?
        !valid?
      end

      sig { void }
      def clear
        @messages.clear
        @details.clear
      end

      sig { returns(T::Array[String]) }
      def full_messages
        @messages.flat_map do |field, msgs|
          msgs.map do |m|
            if field == :base
              m
            else
              "#{field} #{m}"
            end
          end
        end
      end

      sig { returns(Integer) }
      def count
        @messages.values.sum(&:length)
      end
    end
  end

  Errors = Validation::Errors
end
