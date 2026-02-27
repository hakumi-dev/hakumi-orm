# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      class Exclusion
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          blocked = resolve_values(rule[:in], context)
          return unless blocked.include?(context.value)

          context.add_error(rule: rule, type: :exclusion, default_message: "is reserved")
        end

        private

        sig { params(raw: T.nilable(Object), context: RuleContext).returns(T::Array[Object]) }
        def resolve_values(raw, context)
          values = context.resolve_value(raw)
          return values if values.is_a?(Array)

          raise ArgumentError, "exclusion validator requires :in Array or callable returning Array"
        end
      end
    end
  end
end
