# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    # Runtime context passed to each validator.
    class RuleContext
      extend T::Sig

      sig { returns(Symbol) }
      attr_reader :attribute

      sig { returns(Object) }
      attr_reader :value

      sig { returns(HakumiORM::Errors) }
      attr_reader :errors

      sig { returns(Object) }
      attr_reader :record

      sig { params(attribute: Symbol, value: Object, errors: HakumiORM::Errors, record: Object).void }
      def initialize(attribute:, value:, errors:, record:)
        @attribute = attribute
        @value = value
        @errors = errors
        @record = record
      end

      sig { returns(T::Boolean) }
      def blank_value?
        raw = value
        return true if raw.nil?
        return raw.strip.empty? if raw.is_a?(String)
        return raw.empty? if raw.is_a?(Array) || raw.is_a?(Hash)

        false
      end

      sig { returns(T.nilable(Integer)) }
      def value_length
        raw = value
        return raw.length if raw.is_a?(String) || raw.is_a?(Array) || raw.is_a?(Hash)

        nil
      end

      sig { returns(T.nilable(Float)) }
      def to_numeric
        raw = value
        return raw.to_f if raw.is_a?(Numeric)
        return nil unless raw.is_a?(String)

        Float(raw)
      rescue ArgumentError, TypeError
        nil
      end

      sig { returns(T::Boolean) }
      def integer_value?
        raw = value
        return true if raw.is_a?(Integer)
        return false unless raw.is_a?(String)

        Integer(raw, 10)
        true
      rescue ArgumentError
        false
      end

      sig { params(rule: RulePayload, type: Symbol, default_message: String).void }
      def add_error(rule:, type:, default_message:)
        custom = rule[:message]
        resolved = resolve_value(custom)
        message = resolved.is_a?(String) ? resolved : default_message
        errors.add(attribute, message, type: type)
      end

      sig { params(raw: T.nilable(Object)).returns(Object) }
      def resolve_value(raw)
        return nil if raw.nil?
        return raw unless raw.is_a?(Proc)

        case raw.arity
        when 0
          raw.call
        when 1
          raw.call(record)
        else
          raw.call(record, self)
        end
      end
    end
  end
end
