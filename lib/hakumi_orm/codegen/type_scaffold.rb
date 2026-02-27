# typed: strict
# frozen_string_literal: true

# Internal component for codegen/type_scaffold.
module HakumiORM
  module Codegen
    # Internal module for HakumiORM.
    module TypeScaffold
      class << self
        extend T::Sig

        sig { params(name: String, output_dir: String).void }
        def generate(name:, output_dir:)
          class_name = camelize(name)
          generate_field(name, class_name, output_dir)
          generate_registration(name, class_name, output_dir)
        end

        private

        sig { params(name: String, class_name: String, output_dir: String).void }
        def generate_field(name, class_name, output_dir)
          path = File.join(output_dir, "#{name}_field.rb")
          return if File.exist?(path)

          File.write(path, field_template(class_name))
        end

        sig { params(name: String, class_name: String, output_dir: String).void }
        def generate_registration(name, class_name, output_dir)
          path = File.join(output_dir, "#{name}_type.rb")
          return if File.exist?(path)

          File.write(path, registration_template(name, class_name))
        end

        sig { params(class_name: String).returns(String) }
        def field_template(class_name)
          <<~RUBY
            # typed: strict
            # frozen_string_literal: true

            class #{class_name}Field < ::HakumiORM::Field
              extend T::Sig

              ValueType = type_member { { fixed: String } }

              sig { override.params(value: String).returns(::HakumiORM::Bind) }
              def to_bind(value)
                ::HakumiORM::StrBind.new(value)
              end
            end
          RUBY
        end

        sig { params(name: String, class_name: String).returns(String) }
        def registration_template(name, class_name)
          <<~RUBY
            # typed: strict
            # frozen_string_literal: true

            HakumiORM::Codegen::TypeRegistry.register(
              name: :#{name},
              ruby_type: "String",
              cast_expression: lambda { |raw_expr, nullable|
                nullable ? "((_hv = \#{raw_expr}).nil? ? nil : \#{raw_expr})" : raw_expr
              },
              field_class: "::#{class_name}Field",
              bind_class: "::HakumiORM::StrBind"
            )
          RUBY
        end

        sig { params(name: String).returns(String) }
        def camelize(name)
          name.split("_").map(&:capitalize).join
        end
      end
    end
  end
end
