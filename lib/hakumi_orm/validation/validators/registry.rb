# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      # Resolves validator instances by validation kind.
      module Registry
        extend T::Sig

        BUILT_IN_VALIDATORS = T.let({
          presence: Presence.new,
          blank: Blank.new,
          length: Length.new,
          format: Format.new,
          numericality: Numericality.new,
          inclusion: Inclusion.new,
          exclusion: Exclusion.new,
          comparison: Comparison.new
        }.freeze, T::Hash[Symbol, Base])

        sig { params(kind: Symbol, validator: Base).void }
        def self.register(kind, validator)
          raise ArgumentError, "Validator #{kind.inspect} is already registered" if registry.key?(kind)

          registry[kind] = validator
        end

        sig { params(kind: Symbol).returns(T::Boolean) }
        def self.registered?(kind)
          registry.key?(kind)
        end

        sig { params(kind: Symbol).returns(Base) }
        def self.fetch(kind)
          registry.fetch(kind) do
            raise ArgumentError, "Unsupported validation kind #{kind.inspect}"
          end
        end

        sig { void }
        def self.reset!
          @registry = T.let(BUILT_IN_VALIDATORS.dup, T.nilable(T::Hash[Symbol, Base]))
        end

        sig { returns(T::Hash[Symbol, Base]) }
        def self.registry
          @registry ||= T.let(BUILT_IN_VALIDATORS.dup, T.nilable(T::Hash[Symbol, Base]))
        end
        private_class_method :registry
      end
    end
  end
end
