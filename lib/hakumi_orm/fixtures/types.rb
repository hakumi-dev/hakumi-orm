# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Fixtures
    # Shared Sorbet type aliases used by fixture loading components.
    module Types
      FixtureScalar = T.type_alias do
        T.nilable(T.any(String, Integer, Float, BigDecimal, Date, Time, T::Boolean, Symbol))
      end

      FixtureValue = T.type_alias do
        T.any(
          FixtureScalar,
          T::Array[FixtureScalar],
          T::Hash[String, FixtureScalar],
          T::Hash[Symbol, FixtureScalar]
        )
      end

      FixtureRow = T.type_alias { T::Hash[String, FixtureValue] }
      FixtureRowSet = T.type_alias { T::Hash[String, FixtureRow] }
      LoadedFixtures = T.type_alias { T::Hash[String, FixtureRowSet] }
      LoadPlan = T.type_alias do
        {
          table_count: Integer,
          row_count: Integer,
          table_rows: T::Hash[String, Integer]
        }
      end
    end
  end
end
