# typed: false
# frozen_string_literal: true

require_relative "../test_helper"

class TestPublicApiContract < Minitest::Test
  def test_public_operations_expose_fixtures_load
    assert_respond_to HakumiORM::Application::FixturesLoad, :load!
    assert_respond_to HakumiORM::Application::FixturesLoad, :load_with_data!
    assert_respond_to HakumiORM::Application::FixturesLoad, :plan_load!
  end

  def test_public_orchestration_does_not_reference_internal_fixture_loader_directly
    root = File.expand_path("../..", __dir__)
    public_files = [
      File.join(root, "lib/hakumi_orm/task_commands.rb"),
      File.join(root, "lib/hakumi_orm/test_fixtures.rb")
    ]

    public_files.each do |path|
      content = File.read(path)
      refute_match(/HakumiORM::Fixtures::Loader/, content, "direct loader usage leaked in #{path}")
    end
  end

  def test_internal_namespace_exposes_fixture_implementations
    assert_kind_of(Class, HakumiORM::Internal::FixturesLoader)
    assert_kind_of(Class, HakumiORM::Internal::FixturesReferenceResolver)
    assert_kind_of(Class, HakumiORM::Internal::FixturesIntegrityVerifier)
  end
end
