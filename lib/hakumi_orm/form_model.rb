# typed: strict
# frozen_string_literal: true

module HakumiORM
  module FormModel
    # Provides the minimal form interface used by form builders.
    module Default
      extend T::Sig
      include Kernel

      sig { params(base: Module).void }
      def self.included(base)
        base.extend(ClassMethods)
        HakumiORM.config.form_model_adapter.apply_to(base)
      end

      # Class-level API expected by form builders.
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

      sig { returns(HakumiORM::Validation::Errors) }
      def errors
        current = @hakumi_form_errors
        return current if current

        @hakumi_form_errors = T.let(HakumiORM::Validation::Errors.new, T.nilable(HakumiORM::Validation::Errors))
        @hakumi_form_errors || HakumiORM::Validation::Errors.new
      end

      sig { returns(T::Boolean) }
      def valid?
        current = @hakumi_form_errors
        current&.clear
        run_form_model_validation(errors)
        errors.valid?
      end

      sig { returns(T::Boolean) }
      def invalid?
        !valid?
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def to_key
        id = form_model_id
        return nil unless id

        [id]
      end

      sig { returns(T.nilable(String)) }
      def to_param
        id = form_model_id
        id&.to_s
      end

      sig { returns(T::Boolean) }
      def persisted?
        !form_model_id.nil?
      end

      sig { returns(Object) }
      def to_model
        T.cast(self, Object)
      end

      private

      sig { params(_errors: HakumiORM::Validation::Errors).void }
      def run_form_model_validation(_errors); end

      sig { returns(T.nilable(Integer)) }
      def form_model_id
        return nil unless respond_to?(:id)

        value = method(:id).call
        return value if value.is_a?(Integer)

        nil
      end
    end
  end
end
