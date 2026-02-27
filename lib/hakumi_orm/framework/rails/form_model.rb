# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    class Rails
      # Rails-specific form behavior layered on top of the core form model.
      module FormModel
        extend T::Sig
        extend HakumiORM::FormModelAdapter
        include Kernel

        sig { override.params(base: Module).void }
        def self.apply_to(base)
          base.prepend(self) unless base < self
        end

        sig { returns(Object) }
        def to_model
          T.cast(self, Object)
        end

        # Rails-specific class helpers used by ActionView model naming.
        module ClassMethods
          extend T::Sig
          include Kernel

          sig { returns(Object) }
          def model_name
            HakumiORM::FormModel::Name.new(to_s)
          end

          sig { params(attribute: T.any(String, Symbol)).returns(String) }
          def human_attribute_name(attribute)
            attribute.to_s.tr("_", " ").capitalize
          end
        end

        sig { params(base: Module).void }
        def self.prepended(base)
          base.extend(ClassMethods)
        end
      end
    end
  end
end
