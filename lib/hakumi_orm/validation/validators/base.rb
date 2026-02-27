# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      module Base
        extend T::Sig
        extend T::Helpers

        interface!

        sig { abstract.params(context: RuleContext, rule: RulePayload).void }
        def validate(context, rule); end
      end
    end
  end
end
