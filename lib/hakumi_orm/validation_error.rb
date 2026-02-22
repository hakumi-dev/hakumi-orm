# typed: strict
# frozen_string_literal: true

module HakumiORM
  class ValidationError < Error
    extend T::Sig

    sig { returns(Errors) }
    attr_reader :errors

    sig { params(errors: Errors).void }
    def initialize(errors)
      @errors = T.let(errors, Errors)
      super("Validation failed: #{errors.full_messages.join(", ")}")
    end
  end
end
