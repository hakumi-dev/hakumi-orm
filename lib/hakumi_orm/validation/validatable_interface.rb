# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    # Contract for records that expose values to the validation engine.
    module ValidatableInterface
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(attribute: Symbol).returns(T::Boolean) }
      def validation_attribute?(attribute); end

      sig { abstract.params(attribute: Symbol).returns(Object) }
      def validation_value(attribute); end
    end
  end
end
