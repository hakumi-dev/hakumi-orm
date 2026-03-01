# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Built-in word inflection helpers used by codegen, scaffold, and migration DSL.
  # The default singularizer covers common English pluralization rules plus a curated
  # set of uncountable words and irregular pairs drawn from dry-inflector and
  # ActiveSupport, filtered to words likely to appear as database table names.
  #
  # Users can replace or extend it per-environment via the config:
  #
  #   HakumiORM.configure do |c|
  #     c.singularizer = ->(word) {
  #       case word
  #       when "criteria" then "criterion"
  #       else HakumiORM::Inflector.singularize(word)
  #       end
  #     }
  #   end
  module Inflector
    extend T::Sig

    # Words whose singular form equals their plural form.
    # Checked before any suffix rules so they are never accidentally mutated.
    # Source: union of dry-inflector and ActiveSupport uncountables, filtered
    # to words plausible as database table names.
    UNCOUNTABLES = T.let(
      Set.new(%w[data deer equipment fish information jeans metadata money moose news police rice series sheep species]).freeze,
      T::Set[String]
    )

    # Irregular plural → singular pairs that do not follow suffix rules.
    # Checked after uncountables and before suffix rules.
    IRREGULARS = T.let({
      "children" => "child",
      "men" => "man",
      "mice" => "mouse",
      "people" => "person"
    }.freeze, T::Hash[String, String])

    sig { params(word: String).returns(String) }
    def self.singularize(word)
      return word if UNCOUNTABLES.include?(word)
      return IRREGULARS.fetch(word) if IRREGULARS.key?(word)
      return "#{word.delete_suffix("ies")}y" if word.end_with?("ies")
      return "#{word.delete_suffix("ves")}f" if word.end_with?("ves")
      return word.delete_suffix("es") if word.end_with?("ses", "xes", "zes", "ches", "shes")
      return word.delete_suffix("s") if word.end_with?("s") && !word.end_with?("ss", "us", "is")

      word
    end
  end
end
