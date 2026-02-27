# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    module Validators
      module Registry
        extend T::Sig

        VALIDATORS = T.let({
          presence: Presence.new,
          blank: Blank.new,
          length: Length.new,
          format: Format.new,
          numericality: Numericality.new,
          inclusion: Inclusion.new,
          exclusion: Exclusion.new,
          comparison: Comparison.new
        }.freeze, T::Hash[Symbol, Base])

        sig { params(kind: Symbol).returns(Base) }
        def self.fetch(kind)
          VALIDATORS.fetch(kind) do
            raise ArgumentError, "Unsupported validation kind #{kind.inspect}"
          end
        end
      end
    end
  end
end
