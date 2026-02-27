# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Ensures a value is blank.
      class Blank
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          return if context.blank_value?

          context.add_error(rule: rule, type: :present, default_message: "must be blank")
        end
      end
    end
  end
end
