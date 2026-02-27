# typed: strict
# frozen_string_literal: true

# Internal component for migration/table_definition.
module HakumiORM
  class Migration
    # Internal class for HakumiORM.
    class TableDefinition
      extend T::Sig

      VALID_TYPES = T.let(
        %i[
          string text integer bigint float decimal boolean
          date datetime timestamp binary json jsonb uuid
          inet cidr hstore
          integer_array string_array float_array boolean_array
        ].freeze,
        T::Array[Symbol]
      )

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.any(Symbol, FalseClass)) }
      attr_reader :id_type

      sig { returns(T::Array[ColumnDefinition]) }
      attr_reader :columns

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      attr_reader :foreign_keys

      sig { returns(T.nilable(T::Array[String])) }
      attr_reader :composite_primary_key

      sig { params(name: String, id: T.any(Symbol, FalseClass)).void }
      def initialize(name, id: :bigserial)
        @name = T.let(name, String)
        @id_type = T.let(id, T.any(Symbol, FalseClass))
        @columns = T.let([], T::Array[ColumnDefinition])
        @foreign_keys = T.let([], T::Array[T::Hash[Symbol, String]])
        @composite_primary_key = T.let(nil, T.nilable(T::Array[String]))
      end

      sig { params(col_name: Migration::NameLike, type: Symbol, null: T::Boolean, default: Migration::DefaultValue, limit: T.nilable(Integer), precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
      def column(col_name, type, null: true, default: nil, limit: nil, precision: nil, scale: nil)
        unless VALID_TYPES.include?(type)
          raise HakumiORM::Error, "Unknown column type: :#{type}. Valid types: #{VALID_TYPES.map { |t| ":#{t}" }.join(", ")}"
        end

        @columns << ColumnDefinition.new(
          name: col_name.to_s, type: type, null: null, default: Migration.coerce_default(default),
          limit: limit, precision: precision, scale: scale
        )
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue, limit: T.nilable(Integer)).void }
      def string(col_name, null: true, default: nil, limit: nil)
        column(col_name, :string, null: null, default: default, limit: limit)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def text(col_name, null: true, default: nil)
        column(col_name, :text, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue, limit: T.nilable(Integer)).void }
      def integer(col_name, null: true, default: nil, limit: nil)
        column(col_name, :integer, null: null, default: default, limit: limit)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def bigint(col_name, null: true, default: nil)
        column(col_name, :bigint, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def float(col_name, null: true, default: nil)
        column(col_name, :float, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue, precision: T.nilable(Integer), scale: T.nilable(Integer)).void }
      def decimal(col_name, null: true, default: nil, precision: nil, scale: nil)
        column(col_name, :decimal, null: null, default: default, precision: precision, scale: scale)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def boolean(col_name, null: true, default: nil)
        column(col_name, :boolean, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def date(col_name, null: true, default: nil)
        column(col_name, :date, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def datetime(col_name, null: true, default: nil)
        column(col_name, :datetime, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def timestamp(col_name, null: true, default: nil)
        column(col_name, :timestamp, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def binary(col_name, null: true)
        column(col_name, :binary, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def json(col_name, null: true, default: nil)
        column(col_name, :json, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def jsonb(col_name, null: true, default: nil)
        column(col_name, :jsonb, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def uuid(col_name, null: true, default: nil)
        column(col_name, :uuid, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def inet(col_name, null: true)
        column(col_name, :inet, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def cidr(col_name, null: true)
        column(col_name, :cidr, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean, default: Migration::DefaultValue).void }
      def hstore(col_name, null: true, default: nil)
        column(col_name, :hstore, null: null, default: default)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def integer_array(col_name, null: true)
        column(col_name, :integer_array, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def string_array(col_name, null: true)
        column(col_name, :string_array, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def float_array(col_name, null: true)
        column(col_name, :float_array, null: null)
      end

      sig { params(col_name: Migration::NameLike, null: T::Boolean).void }
      def boolean_array(col_name, null: true)
        column(col_name, :boolean_array, null: null)
      end

      sig { params(created_at: Migration::NameLike, updated_at: Migration::NameLike, null: T::Boolean).void }
      def timestamps(created_at: "created_at", updated_at: "updated_at", null: false)
        column(created_at, :timestamp, null: null)
        column(updated_at, :timestamp, null: null)
      end

      sig { params(cols: T::Array[String]).void }
      def primary_key(cols)
        @composite_primary_key = cols
      end

      sig { params(table_name: Migration::NameLike, foreign_key: T::Boolean, null: T::Boolean, primary_key: String, column: T.nilable(String)).void }
      def references(table_name, foreign_key: false, null: false, primary_key: "id", column: nil)
        table_name = table_name.to_s
        col_name = column || "#{singularize(table_name)}_id"
        self.column(col_name, :bigint, null: null)
        return unless foreign_key

        @foreign_keys << { column: col_name, to_table: table_name, primary_key: primary_key }
      end

      private

      sig { params(word: String).returns(String) }
      def singularize(word)
        if word.end_with?("ies")
          "#{word.delete_suffix("ies")}y"
        elsif word.end_with?("ses", "xes", "zes", "ches", "shes")
          word.delete_suffix("es")
        elsif word.end_with?("s") && !word.end_with?("ss", "us", "is")
          word.delete_suffix("s")
        else
          word
        end
      end
    end
  end
end
