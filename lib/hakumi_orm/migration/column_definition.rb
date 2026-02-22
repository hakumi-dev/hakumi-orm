# typed: strict
# frozen_string_literal: true

module HakumiORM
  class Migration
    class ColumnDefinition < T::Struct
      const :name, String
      const :type, Symbol
      const :null, T::Boolean, default: true
      const :default, T.nilable(String), default: nil
      const :limit, T.nilable(Integer), default: nil
      const :precision, T.nilable(Integer), default: nil
      const :scale, T.nilable(Integer), default: nil
    end
  end
end
