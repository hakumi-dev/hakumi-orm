# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Validates that a value belongs to a whitelist.
      class Inclusion
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          allowed = resolve_values(rule[:in], context)
          return if allowed.include?(context.value)

          context.add_error(rule: rule, type: :inclusion, default_message: "is not included in the list")
        end

        private

        sig { params(raw: T.nilable(Object), context: RuleContext).returns(T::Array[Object]) }
        def resolve_values(raw, context)
          values = context.resolve_value(raw)
          return values if values.is_a?(Array)

          raise ArgumentError, "inclusion validator requires :in Array or callable returning Array"
        end
      end
    end
  end
end
