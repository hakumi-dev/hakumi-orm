# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module ContractDSL
      private

      sig { params(length: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_length_options(length)
        {
          minimum: fetch_integer_option(length, :minimum),
          maximum: fetch_integer_option(length, :maximum),
          is: fetch_integer_option(length, :is)
        }
      end

      sig { params(format: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_format_options(format)
        pattern = format[:with]
        raise ArgumentError, "format validator requires :with Regexp or callable" unless pattern.is_a?(Regexp) || pattern.is_a?(Proc)

        { with: pattern }
      end

      sig { params(inclusion: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_inclusion_options(inclusion)
        values = inclusion[:in]
        raise ArgumentError, "inclusion validator requires :in Array or callable" unless values.is_a?(Array) || values.is_a?(Proc)

        { in: values }
      end

      sig { params(exclusion: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_exclusion_options(exclusion)
        values = exclusion[:in]
        raise ArgumentError, "exclusion validator requires :in Array or callable" unless values.is_a?(Array) || values.is_a?(Proc)

        { in: values }
      end

      sig { params(numericality: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_numericality_options(numericality)
        {
          only_integer: fetch_boolean_option(numericality, :only_integer, false),
          greater_than: fetch_float_option(numericality, :greater_than),
          greater_than_or_equal_to: fetch_float_option(numericality, :greater_than_or_equal_to),
          less_than: fetch_float_option(numericality, :less_than),
          less_than_or_equal_to: fetch_float_option(numericality, :less_than_or_equal_to)
        }
      end

      sig { params(comparison: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def parse_comparison_options(comparison)
        allowed = %i[greater_than greater_than_or_equal_to less_than less_than_or_equal_to equal_to other_than]
        rules = comparison.slice(*allowed)
        raise ArgumentError, "comparison validator requires at least one comparison option" if rules.empty?

        result = T.let({}, HakumiORM::Validation::RulePayload)
        rules.each { |key, value| result[key] = normalize_comparison_operand(value) }
        result
      end

      sig { params(value: Object).returns(T.any(Symbol, String, Integer, Float, Proc)) }
      def normalize_comparison_operand(value)
        return value if value.is_a?(Symbol)
        return value if value.is_a?(String)
        return value if value.is_a?(Integer)
        return value if value.is_a?(Float)
        return value if value.is_a?(Proc)

        raise ArgumentError, "comparison operand must be Symbol, Numeric, String, or callable"
      end

      sig { params(options: T::Hash[Symbol, Object], key: Symbol).returns(T.nilable(Integer)) }
      def fetch_integer_option(options, key)
        value = options[key]
        return nil if value.nil?
        return value if value.is_a?(Integer)

        raise ArgumentError, "#{key} must be Integer"
      end

      sig { params(options: T::Hash[Symbol, Object], key: Symbol).returns(T.nilable(Float)) }
      def fetch_float_option(options, key)
        value = options[key]
        return nil if value.nil?
        return value.to_f if value.is_a?(Numeric)

        raise ArgumentError, "#{key} must be Numeric"
      end

      sig { params(options: T::Hash[Symbol, Object], key: Symbol, default: T::Boolean).returns(T::Boolean) }
      def fetch_boolean_option(options, key, default)
        value = options[key]
        return default if value.nil?
        return T.cast(value, T::Boolean) if [true, false].include?(value)

        raise ArgumentError, "#{key} must be true/false"
      end

      sig { params(rule: HakumiORM::Validation::RulePayload, record: Object, errors: HakumiORM::Errors).void }
      def run_custom_validation(rule, record, errors)
        method_name = T.cast(rule[:method], Symbol)
        raise ArgumentError, "Custom validation method #{method_name.inspect} is not defined on #{self}" unless respond_to?(method_name)

        public_send(method_name, record, errors)
      end
    end
  end
end
