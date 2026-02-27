# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Ensures a value is present.
      class Presence
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          return unless context.blank_value?

          context.add_error(rule: rule, type: :blank, default_message: "can't be blank")
        end
      end
    end
  end
end
