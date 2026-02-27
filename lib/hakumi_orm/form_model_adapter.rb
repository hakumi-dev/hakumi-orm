# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Contract for objects that apply form-model behavior into record classes.
  module FormModelAdapter
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.params(base: Module).void }
    def apply_to(base); end
  end
end
