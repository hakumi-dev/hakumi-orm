# typed: false
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "hakumi_orm"
require "hakumi_orm/codegen"
require "minitest/autorun"
require_relative "support/mock_adapter"
require_relative "support/fixtures"

module HakumiORM
  class TestCase < Minitest::Test
    def self.test(name, &)
      method_name = "test_#{name.gsub(/\s+/, "_")}"
      define_method(method_name, &)
    end
  end
end
