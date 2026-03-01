# typed: false
# frozen_string_literal: true

require "test_helper"

class TestInflector < HakumiORM::TestCase
  # --- Built-in Inflector rules ---

  test "singularizes -ies ending" do
    assert_equal "category", HakumiORM::Inflector.singularize("categories")
    assert_equal "party", HakumiORM::Inflector.singularize("parties")
  end

  test "singularizes -ves ending" do
    assert_equal "wolf", HakumiORM::Inflector.singularize("wolves")
    assert_equal "leaf", HakumiORM::Inflector.singularize("leaves")
  end

  test "singularizes -ses, -xes, -zes, -ches, -shes endings" do
    assert_equal "bus", HakumiORM::Inflector.singularize("buses")
    assert_equal "box", HakumiORM::Inflector.singularize("boxes")
    assert_equal "buzz", HakumiORM::Inflector.singularize("buzzes")
    assert_equal "church", HakumiORM::Inflector.singularize("churches")
    assert_equal "dish", HakumiORM::Inflector.singularize("dishes")
  end

  test "singularizes simple -s ending" do
    assert_equal "user", HakumiORM::Inflector.singularize("users")
    assert_equal "post", HakumiORM::Inflector.singularize("posts")
  end

  test "leaves -ss, -us, -is words unchanged" do
    assert_equal "status", HakumiORM::Inflector.singularize("status")
    assert_equal "analysis", HakumiORM::Inflector.singularize("analysis")
    assert_equal "class", HakumiORM::Inflector.singularize("class")
  end

  test "leaves already-singular words unchanged" do
    assert_equal "person", HakumiORM::Inflector.singularize("person")
    assert_equal "data", HakumiORM::Inflector.singularize("data")
  end

  # --- Uncountables ---

  test "uncountable words are returned unchanged" do
    %w[data deer equipment fish information jeans metadata money moose
       news police rice series sheep species].each do |word|
      assert_equal word, HakumiORM::Inflector.singularize(word),
                   "expected #{word.inspect} to be unchanged (uncountable)"
    end
  end

  test "series and species are not garbled by -ies rule" do
    # Without uncountables these would become "sery" and "specy"
    assert_equal "series",  HakumiORM::Inflector.singularize("series")
    assert_equal "species", HakumiORM::Inflector.singularize("species")
  end

  test "news is not stripped to new" do
    assert_equal "news", HakumiORM::Inflector.singularize("news")
  end

  # --- Irregulars ---

  test "people singularizes to person" do
    assert_equal "person", HakumiORM::Inflector.singularize("people")
  end

  test "men singularizes to man" do
    assert_equal "man", HakumiORM::Inflector.singularize("men")
  end

  test "children singularizes to child" do
    assert_equal "child", HakumiORM::Inflector.singularize("children")
  end

  test "mice singularizes to mouse" do
    assert_equal "mouse", HakumiORM::Inflector.singularize("mice")
  end

  # --- HakumiORM.singularize convenience method ---

  test "HakumiORM.singularize delegates to config singularizer" do
    assert_equal "user", HakumiORM.singularize("users")
    assert_equal "category", HakumiORM.singularize("categories")
  end

  # --- Custom singularizer via config ---

  test "singularizer config defaults to built-in Inflector" do
    config = HakumiORM::Configuration.new
    assert_respond_to config.singularizer, :call
    assert_equal "user", config.singularizer.call("users")
  end

  test "custom singularizer proc is called by HakumiORM.singularize" do
    HakumiORM.config.singularizer = ->(word) { "custom_#{word}" }

    assert_equal "custom_users", HakumiORM.singularize("users")
  ensure
    HakumiORM.reset_config!
  end

  test "custom singularizer handles irregular words" do
    overrides = { "people" => "person", "criteria" => "criterion", "media" => "medium" }
    HakumiORM.config.singularizer = lambda { |word|
      overrides[word] || HakumiORM::Inflector.singularize(word)
    }

    assert_equal "person", HakumiORM.singularize("people")
    assert_equal "criterion", HakumiORM.singularize("criteria")
    assert_equal "medium", HakumiORM.singularize("media")
    assert_equal "user", HakumiORM.singularize("users")
  ensure
    HakumiORM.reset_config!
  end

  test "custom singularizer affects scaffold generator" do
    Dir.mktmpdir do |dir|
      HakumiORM.config.singularizer = ->(word) { word == "people" ? "person" : HakumiORM::Inflector.singularize(word) }
      HakumiORM.config.models_dir = dir
      HakumiORM.config.contracts_dir = nil

      gen = HakumiORM::ScaffoldGenerator.new("people", HakumiORM.config)
      gen.run!

      assert_path_exists File.join(dir, "person.rb")
    end
  ensure
    HakumiORM.reset_config!
  end

  test "custom singularizer affects migration references column name" do
    HakumiORM.config.singularizer = ->(word) { word == "people" ? "person" : HakumiORM::Inflector.singularize(word) }

    td = HakumiORM::Migration::TableDefinition.new("posts")
    td.references "people"

    person_col = td.columns.find { |c| c.name == "person_id" }
    assert person_col, "Expected person_id column to be created from custom singularizer"
  ensure
    HakumiORM.reset_config!
  end
end
