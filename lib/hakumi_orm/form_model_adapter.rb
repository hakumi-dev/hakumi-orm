# typed: strict
# frozen_string_literal: true

module HakumiORM
  module FormModel
    # Marker interface for classes that receive form-model behavior.
    module Host
      extend T::Sig
      extend T::Helpers

      interface!
    end
  end

  # Contract for objects that apply form-model behavior into record classes.
  module FormModelAdapter
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.params(base: T::Class[FormModel::Host]).void }
    def apply_to(base); end
  end
end
