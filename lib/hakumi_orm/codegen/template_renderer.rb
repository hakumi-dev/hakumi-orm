# typed: strict
# frozen_string_literal: true

require "erb"

module HakumiORM
  module Codegen
    # Renders codegen ERB templates from the `templates/` directory.
    class TemplateRenderer
      extend T::Sig

      TEMPLATE_DIR = T.let(
        File.join(File.dirname(File.expand_path(__FILE__)), "templates").freeze,
        String
      )

      sig { void }
      def initialize
        @templates = T.let({}, T::Hash[String, ERB])
      end

      sig { params(template_name: String, locals: T::Hash[Symbol, TemplateLocal]).returns(String) }
      def render(template_name, locals)
        template = @templates[template_name]
        unless template
          path = File.join(TEMPLATE_DIR, "#{template_name}.rb.tt")
          template = ERB.new(File.read(path), trim_mode: "-")
          @templates[template_name] = template
        end

        T.cast(template.result_with_hash(locals), String)
      end
    end
  end
end
