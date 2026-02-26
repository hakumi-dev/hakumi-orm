# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Codegen
    # Computes filesystem paths for generated code and optional user stubs.
    class GenerationPlan
      extend T::Sig

      sig do
        params(
          output_dir: String,
          models_dir: T.nilable(String),
          contracts_dir: T.nilable(String),
          module_name: T.nilable(String)
        ).void
      end
      def initialize(output_dir:, models_dir:, contracts_dir:, module_name:)
        @output_dir = T.let(output_dir, String)
        @models_dir = T.let(models_dir, T.nilable(String))
        @contracts_dir = T.let(contracts_dir, T.nilable(String))
        @module_name = T.let(module_name, T.nilable(String))
      end

      sig { returns(String) }
      attr_reader :output_dir

      sig { returns(T.nilable(String)) }
      attr_reader :models_dir

      sig { returns(T.nilable(String)) }
      attr_reader :contracts_dir

      sig { params(singular_table_name: String).returns(String) }
      def table_dir(singular_table_name)
        File.join(@output_dir, singular_table_name)
      end

      sig { params(singular_table_name: String, file_name: String).returns(String) }
      def table_file_path(singular_table_name, file_name)
        File.join(table_dir(singular_table_name), file_name)
      end

      sig { returns(String) }
      def manifest_path
        File.join(@output_dir, "manifest.rb")
      end

      sig { returns(T.nilable(String)) }
      def models_root_dir
        dir = @models_dir
        return nil unless dir

        namespaced_user_dir(dir)
      end

      sig { returns(T.nilable(String)) }
      def contracts_root_dir
        dir = @contracts_dir
        return nil unless dir

        namespaced_user_dir(dir)
      end

      sig { params(singular_table_name: String).returns(T.nilable(String)) }
      def model_stub_path(singular_table_name)
        root = models_root_dir
        return nil unless root

        File.join(root, "#{singular_table_name}.rb")
      end

      sig { params(singular_table_name: String).returns(T.nilable(String)) }
      def contract_stub_path(singular_table_name)
        root = contracts_root_dir
        return nil unless root

        File.join(root, "#{singular_table_name}_contract.rb")
      end

      sig { params(singular_table_name: String).returns(T.nilable(String)) }
      def model_variant_dir(singular_table_name)
        root = models_root_dir
        return nil unless root

        File.join(root, singular_table_name)
      end

      private

      sig { params(base_dir: String).returns(String) }
      def namespaced_user_dir(base_dir)
        mod = @module_name
        return base_dir unless mod

        path = T.let(base_dir, String)
        mod.split("::").each do |part|
          path = File.join(path, underscore(part))
        end
        path
      end

      sig { params(name: String).returns(String) }
      def underscore(name)
        name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("-", "_")
          .downcase
      end
    end
  end
end
