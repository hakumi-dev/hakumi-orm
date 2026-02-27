# typed: strict
# frozen_string_literal: true

# Internal component for field/text_field.
module HakumiORM
  # Internal class for HakumiORM.
  class TextField < Field
    extend T::Sig
    extend T::Helpers

    abstract!

    ValueType = type_member

    sig { params(pattern: String).returns(Predicate) }
    def like(pattern)
      Predicate.new(self, :like, [StrBind.new(pattern)])
    end

    sig { params(pattern: String).returns(Predicate) }
    def ilike(pattern)
      Predicate.new(self, :ilike, [StrBind.new(pattern)])
    end
  end
end
