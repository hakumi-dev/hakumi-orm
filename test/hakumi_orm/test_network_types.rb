# typed: false
# frozen_string_literal: true

require "test_helper"

class TestNetworkTypes < HakumiORM::TestCase
  test "PG type map resolves inet to String" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "inet")

    assert_equal HakumiORM::Codegen::HakumiType::String, ht
  end

  test "PG type map resolves cidr to String" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "cidr")

    assert_equal HakumiORM::Codegen::HakumiType::String, ht
  end

  test "PG type map resolves macaddr to String" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "macaddr")

    assert_equal HakumiORM::Codegen::HakumiType::String, ht
  end

  test "PG type map resolves hstore via udt_name to String" do
    ht = HakumiORM::Codegen::TypeMap.hakumi_type(:postgresql, "USER-DEFINED", "hstore")

    assert_equal HakumiORM::Codegen::HakumiType::String, ht
  end

  test "inet column uses StrField" do
    assert_equal "::HakumiORM::StrField", HakumiORM::Codegen::HakumiType::String.field_class
  end

  test "inet column uses StrBind" do
    assert_equal "::HakumiORM::StrBind", HakumiORM::Codegen::HakumiType::String.bind_class
  end

  test "custom type can override inet to a richer type" do
    HakumiORM::Codegen::TypeRegistry.register(
      name: :inet,
      ruby_type: "IPAddr",
      cast_expression: lambda { |raw_expr, nullable|
        nullable ? "((_hv = #{raw_expr}).nil? ? nil : IPAddr.new(_hv))" : "IPAddr.new(#{raw_expr})"
      },
      field_class: "::MyApp::InetField",
      bind_class: "::MyApp::InetBind"
    )
    HakumiORM::Codegen::TypeRegistry.map_pg_type("inet", :inet)

    entry = HakumiORM::Codegen::TypeRegistry.resolve_pg("inet")

    assert_equal "IPAddr", entry.ruby_type
    assert_equal "::MyApp::InetField", entry.field_class
  ensure
    HakumiORM::Codegen::TypeRegistry.reset!
  end
end
