# typed: strict
# frozen_string_literal: true

require_relative "fixtures/loader"
require_relative "fixtures/reference_resolver"
require_relative "fixtures/integrity_verifier"

module HakumiORM
  # Namespace for internal, non-public implementation constants.
  module Internal
    FixturesLoader = Fixtures::Loader
    FixturesReferenceResolver = Fixtures::ReferenceResolver
    FixturesIntegrityVerifier = Fixtures::IntegrityVerifier
  end
end
