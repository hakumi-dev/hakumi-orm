# typed: strict
# frozen_string_literal: true

module HakumiORM
  class SchemaDriftError < Error
    extend T::Sig

    sig { params(expected: String, actual: String).void }
    def initialize(expected, actual)
      super(
        "Schema drift detected. " \
        "Expected fingerprint '#{expected[0..7]}...' but got '#{actual[0..7]}...'. " \
        "Run 'rake hakumi:generate' to update generated code or set HAKUMI_ALLOW_SCHEMA_DRIFT=1 to bypass."
      )
    end
  end
end
