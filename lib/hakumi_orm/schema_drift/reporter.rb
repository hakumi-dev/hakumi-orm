# typed: strict
# frozen_string_literal: true

module HakumiORM
  module SchemaDrift
    class Reporter
      extend T::Sig

      sig { params(versions: T::Array[String]).returns(T::Array[String]) }
      def self.pending_migrations(versions)
        lines = T.let(["#{versions.size} pending migration(s):"], T::Array[String])
        versions.each { |v| lines << "  - #{v}" }
        lines << ""
        lines << "  Run 'rake db:migrate' to apply."
        lines
      end

      sig { returns(T::Array[String]) }
      def self.no_schema_fingerprint
        ["No schema fingerprint stored. Run 'rake db:generate' first."]
      end

      sig { params(expected: String, actual: String, diff_lines: T::Array[String]).returns(T::Array[String]) }
      def self.schema_drift(expected:, actual:, diff_lines:)
        lines = T.let(["Schema drift detected!"], T::Array[String])
        lines << ""
        lines << "  Expected: #{expected[0..15]}..."
        lines << "  Actual:   #{actual[0..15]}..."

        unless diff_lines.empty?
          lines << ""
          diff_lines.each { |l| lines << "  #{l}" }
        end

        lines << ""
        lines << "  Run 'rake db:generate' to update generated code."
        lines
      end
    end
  end
end
