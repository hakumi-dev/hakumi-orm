# typed: strict
# frozen_string_literal: true

module HakumiORM
  module FormModel
    # Default adapter used when no framework-specific adapter is configured.
    module NoopAdapter
      extend T::Sig
      extend HakumiORM::FormModelAdapter
      include Kernel

      sig { override.params(base: Module).void }
      def self.apply_to(base)
        base.prepend(self) unless base < self
      end

      sig { returns(Object) }
      def to_model
        return T.cast(super, Object) if defined?(super)

        T.cast(self, Object)
      end
    end
  end
end
