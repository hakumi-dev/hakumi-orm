# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      class Length
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          length = context.value_length
          unless length
            context.add_error(rule: rule, type: :invalid, default_message: "has no measurable length")
            return
          end

          exact = rule[:is]
          minimum = rule[:minimum]
          maximum = rule[:maximum]
          if exact && length != T.cast(exact, Integer)
            context.add_error(rule: rule, type: :wrong_length, default_message: "length must be #{exact}")
            return
          end
          if minimum && length < T.cast(minimum, Integer)
            context.add_error(rule: rule, type: :too_short, default_message: "is too short (minimum is #{minimum})")
          end
          return unless maximum && length > T.cast(maximum, Integer)

          context.add_error(rule: rule, type: :too_long, default_message: "is too long (maximum is #{maximum})")
        end
      end
    end
  end
end
