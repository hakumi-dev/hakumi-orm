# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Validates numeric coercion and numeric comparison options.
      class Numericality
        extend T::Sig
        include Base

        sig { override.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule)
          numeric = context.to_numeric
          unless numeric
            context.add_error(rule: rule, type: :not_a_number, default_message: "is not a number")
            return
          end
          if T.cast(rule[:only_integer], T::Boolean) && !context.integer_value?
            context.add_error(rule: rule, type: :not_an_integer, default_message: "must be an integer")
            return
          end

          gt = rule[:greater_than]
          gte = rule[:greater_than_or_equal_to]
          lt = rule[:less_than]
          lte = rule[:less_than_or_equal_to]
          if gt && numeric <= T.cast(gt, Float)
            context.add_error(rule: rule, type: :greater_than, default_message: "must be greater than #{gt}")
          end
          if gte && numeric < T.cast(gte, Float)
            context.add_error(rule: rule, type: :greater_than_or_equal_to, default_message: "must be greater than or equal to #{gte}")
          end
          context.add_error(rule: rule, type: :less_than, default_message: "must be less than #{lt}") if lt && numeric >= T.cast(lt, Float)
          return unless lte && numeric > T.cast(lte, Float)

          context.add_error(rule: rule, type: :less_than_or_equal_to, default_message: "must be less than or equal to #{lte}")
        end
      end
    end
  end
end
