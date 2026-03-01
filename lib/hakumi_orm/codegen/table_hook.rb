# typed: strict
# frozen_string_literal: true

# Internal component for codegen/table_hook.
module HakumiORM
  module Codegen
    # Per-table generation hook: skip table output or inject custom annotation lines.
    class TableHook
      extend T::Sig

      sig { returns(T::Boolean) }
      attr_reader :skip

      sig { returns(T::Array[String]) }
      attr_reader :annotation_lines

      sig { params(skip: T::Boolean, annotation_lines: T::Array[String]).void }
      def initialize(skip: false, annotation_lines: [])
        @skip = T.let(skip, T::Boolean)
        @annotation_lines = T.let(annotation_lines.dup.freeze, T::Array[String])
      end
    end
  end
end
