# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      class Format
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          pattern = resolve_pattern(rule[:with], context)
          value = context.value
          return if value.is_a?(String) && pattern.match?(value)

          context.add_error(rule: rule, type: :invalid, default_message: "is invalid")
        end

        private

        sig { params(raw: T.nilable(Object), context: RuleContext).returns(Regexp) }
        def resolve_pattern(raw, context)
          value = context.resolve_value(raw)
          return value if value.is_a?(Regexp)

          raise ArgumentError, "format validator requires :with Regexp or callable returning Regexp"
        end
      end
    end
  end
end
