# typed: strict
# frozen_string_literal: true

module HakumiORM
  module FormModel
    # Minimal model-name object compatible with form builders.
    class Name
      extend T::Sig

      sig { returns(String) }
      attr_reader :name

      sig { params(class_name: String).void }
      def initialize(class_name)
        @name = class_name
      end

      sig { returns(String) }
      def singular
        underscore(demodulize(name))
      end

      sig { returns(String) }
      def plural
        pluralize(singular)
      end

      sig { returns(String) }
      def param_key
        singular
      end

      sig { returns(String) }
      def route_key
        plural
      end

      sig { returns(String) }
      def singular_route_key
        singular
      end

      sig { returns(Symbol) }
      def i18n_key
        singular.to_sym
      end

      sig { returns(String) }
      def human
        singular.tr("_", " ").capitalize
      end

      sig { returns(String) }
      def to_s
        name
      end

      private

      sig { params(class_name: String).returns(String) }
      def demodulize(class_name)
        class_name.split("::").last || class_name
      end

      sig { params(value: String).returns(String) }
      def underscore(value)
        value
          .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
          .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
          .tr("-", "_")
          .downcase
      end

      sig { params(value: String).returns(String) }
      def pluralize(value)
        return "#{value[0...-1]}ies" if value.end_with?("y") && value.length > 1
        return "#{value}es" if value.end_with?("s")

        "#{value}s"
      end
    end
  end
end
