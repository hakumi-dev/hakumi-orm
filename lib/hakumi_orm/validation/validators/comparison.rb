# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Compares a value against another value using comparison operators.
      class Comparison
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          compare!(context, rule, :greater_than, :greater_than, "must be greater than")
          compare!(context, rule, :greater_than_or_equal_to, :greater_than_or_equal_to, "must be greater than or equal to")
          compare!(context, rule, :less_than, :less_than, "must be less than")
          compare!(context, rule, :less_than_or_equal_to, :less_than_or_equal_to, "must be less than or equal to")
          compare!(context, rule, :equal_to, :equal_to, "must be equal to")
          compare!(context, rule, :other_than, :other_than, "must be other than")
        end

        private

        sig do
          params(
            context: RuleContext,
            rule: RulePayload,
            option: Symbol,
            error_type: Symbol,
            prefix: String
          ).void
        end
        def compare!(context, rule, option, error_type, prefix)
          left = context.value
          raw_right = rule[option]
          return if raw_right.nil?

          right = resolve_operand(raw_right, context)
          cmp = compare_values(left, right)
          unless cmp
            context.add_error(rule: rule, type: :invalid, default_message: "is not comparable")
            return
          end

          return if comparison_ok?(option, cmp)

          context.add_error(rule: rule, type: error_type, default_message: "#{prefix} #{right}")
        end

        sig { params(option: Symbol, cmp: T.nilable(Integer)).returns(T::Boolean) }
        def comparison_ok?(option, cmp)
          return false if cmp.nil?

          case option
          when :greater_than
            cmp.positive?
          when :greater_than_or_equal_to
            cmp >= 0
          when :less_than
            cmp.negative?
          when :less_than_or_equal_to
            cmp <= 0
          when :equal_to
            cmp.zero?
          when :other_than
            !cmp.zero?
          else
            false
          end
        end

        sig { params(left: Object, right: Object).returns(T.nilable(Integer)) }
        def compare_values(left, right)
          return left <=> right if left.is_a?(Numeric) && right.is_a?(Numeric)
          return left <=> right if left.is_a?(String) && right.is_a?(String)
          return left <=> right if left.is_a?(Time) && right.is_a?(Time)
          return left <=> right if left.is_a?(Date) && right.is_a?(Date)

          nil
        end

        sig { params(raw: Object, context: RuleContext).returns(Object) }
        def resolve_operand(raw, context)
          value = context.resolve_value(raw)
          return context.record.public_send(value) if value.is_a?(Symbol)

          value
        end
      end
    end
  end
end
