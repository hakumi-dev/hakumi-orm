# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    # Runtime mixin that implements the ValidatableInterface contract.
    module Validatable
      extend T::Sig
      include ValidatableInterface
      include Kernel

      sig { override.params(attribute: Symbol).returns(T::Boolean) }
      def validation_attribute?(attribute)
        respond_to?(attribute)
      end

      sig { override.params(attribute: Symbol).returns(Object) }
      def validation_value(attribute)
        unless validation_attribute?(attribute)
          raise ArgumentError, "Validation attribute #{attribute.inspect} is not defined on #{self.class}"
        end

        T.cast(public_send(attribute), Object)
      end
    end
  end
end
