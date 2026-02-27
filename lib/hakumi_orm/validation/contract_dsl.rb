# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Validation
    # DSL used by generated contracts to register and execute validations.
    module ContractDSL
      extend T::Sig
      include Kernel

      VALID_CONTEXTS = T.let(%i[all create update persist destroy].freeze, T::Array[Symbol])
      OPTION_VALIDATORS = T.let(
        %i[length format numericality inclusion exclusion comparison]
          .to_h { |kind| [kind, :"parse_#{kind}_options"] }
          .freeze,
        T::Hash[Symbol, Symbol]
      )

      sig { params(attribute: Symbol, kwargs: T::Hash[Symbol, Object]).void.checked(:never) }
      def validates(attribute, **kwargs)
        normalized = normalize_validation_kwargs(kwargs)
        context = T.cast(normalized[:on], Symbol)
        validate_context!(context)
        add_validation_rules(attribute, normalized)
      end

      sig { params(method_name: Symbol, kwargs: T::Hash[Symbol, Object]).void.checked(:never) }
      def validate(method_name, **kwargs)
        context = context_option(kwargs)
        validate_context!(context)
        add_custom_validation_rule(method_name, context, kwargs)
      end

      sig { void }
      def clear_validations!
        @hakumi_validation_rules = T.let([], T.nilable(T::Array[HakumiORM::Validation::RulePayload]))
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validations_for_all(record, errors)
        run_validation_rules(:all, record, errors)
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validations_for_create(record, errors)
        run_validation_rules(:create, record, errors)
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validations_for_update(record, errors)
        run_validation_rules(:update, record, errors)
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validations_for_persist(record, errors)
        run_validation_rules(:persist, record, errors)
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validations_for_destroy(record, errors)
        run_validation_rules(:destroy, record, errors)
      end

      private

      sig { returns(T::Array[HakumiORM::Validation::RulePayload]) }
      def validation_rules
        rules = T.let(@hakumi_validation_rules, T.nilable(T::Array[HakumiORM::Validation::RulePayload]))
        return rules if rules

        @hakumi_validation_rules = T.let([], T.nilable(T::Array[HakumiORM::Validation::RulePayload]))
        @hakumi_validation_rules || []
      end

      sig { params(context: Symbol).void }
      def validate_context!(context)
        return if VALID_CONTEXTS.include?(context)

        raise ArgumentError, "Unsupported validation context #{context.inspect}. Use one of: #{VALID_CONTEXTS.join(", ")}"
      end

      sig { params(kwargs: T::Hash[Symbol, Object]).returns(HakumiORM::Validation::RulePayload) }
      def normalize_validation_kwargs(kwargs)
        {
          presence: bool_option(kwargs, :presence),
          blank: bool_option(kwargs, :blank),
          absence: bool_option(kwargs, :absence),
          length: hash_option(kwargs, :length),
          format: hash_option(kwargs, :format),
          numericality: hash_option(kwargs, :numericality),
          inclusion: hash_option(kwargs, :inclusion),
          exclusion: hash_option(kwargs, :exclusion),
          comparison: hash_option(kwargs, :comparison),
          on: context_option(kwargs),
          allow_nil: bool_option(kwargs, :allow_nil),
          allow_blank: bool_option(kwargs, :allow_blank),
          if: kwargs[:if],
          unless: kwargs[:unless],
          message: message_option(kwargs)
        }
      end

      sig { params(kwargs: T::Hash[Symbol, Object], key: Symbol).returns(T::Boolean) }
      def bool_option(kwargs, key)
        kwargs[key] == true
      end

      sig { params(kwargs: T::Hash[Symbol, Object], key: Symbol).returns(T.nilable(T::Hash[Symbol, Object])) }
      def hash_option(kwargs, key)
        T.cast(kwargs[key], T.nilable(T::Hash[Symbol, Object]))
      end

      sig { params(kwargs: T::Hash[Symbol, Object]).returns(Symbol) }
      def context_option(kwargs)
        return :all unless kwargs.key?(:on)

        T.cast(kwargs[:on], Symbol)
      end

      sig { params(kwargs: T::Hash[Symbol, Object]).returns(T.nilable(T.any(String, Proc))) }
      def message_option(kwargs)
        message = kwargs[:message]
        return message if message.is_a?(String) || message.is_a?(Proc)

        nil
      end

      sig { params(attribute: Symbol, kind: Symbol, options: HakumiORM::Validation::RulePayload).void }
      def add_validation_rule(attribute, kind, options)
        validation_rules << options.merge(attribute: attribute, kind: kind)
      end

      sig { params(method_name: Symbol, context: Symbol, kwargs: T::Hash[Symbol, Object]).void }
      def add_custom_validation_rule(method_name, context, kwargs)
        validation_rules << {
          method: method_name,
          kind: :custom,
          on: context,
          if: kwargs[:if],
          unless: kwargs[:unless]
        }
      end

      sig { params(attribute: Symbol, normalized: HakumiORM::Validation::RulePayload).void }
      def add_validation_rules(attribute, normalized)
        common_options = {
          allow_nil: T.cast(normalized[:allow_nil], T::Boolean),
          allow_blank: T.cast(normalized[:allow_blank], T::Boolean),
          if: normalized[:if],
          unless: normalized[:unless],
          message: normalized[:message],
          on: T.cast(normalized[:on], Symbol)
        }
        add_simple_validation_rules(attribute, normalized, common_options)
        add_option_validation_rules(attribute, normalized, common_options)
      end

      sig do
        params(
          attribute: Symbol,
          normalized: HakumiORM::Validation::RulePayload,
          common_options: HakumiORM::Validation::RulePayload
        ).void
      end
      def add_simple_validation_rules(attribute, normalized, common_options)
        add_validation_rule(attribute, :presence, common_options) if normalized[:presence] == true
        add_validation_rule(attribute, :blank, common_options) if normalized[:blank] == true || normalized[:absence] == true
      end

      sig do
        params(
          attribute: Symbol,
          normalized: HakumiORM::Validation::RulePayload,
          common_options: HakumiORM::Validation::RulePayload
        ).void
      end
      def add_option_validation_rules(attribute, normalized, common_options)
        OPTION_VALIDATORS.each do |kind, parser|
          add_option_rule(attribute, normalized, common_options, kind, parser)
        end
      end

      sig do
        params(
          attribute: Symbol,
          normalized: HakumiORM::Validation::RulePayload,
          common_options: HakumiORM::Validation::RulePayload,
          kind: Symbol,
          parser: Symbol
        ).void
      end
      def add_option_rule(attribute, normalized, common_options, kind, parser)
        raw = T.cast(normalized[kind], T.nilable(T::Hash[Symbol, Object]))
        return unless raw

        parsed = T.cast(send(parser, raw), HakumiORM::Validation::RulePayload)
        add_validation_rule(attribute, kind, common_options.merge(parsed))
      end

      sig { params(context: Symbol, record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def run_validation_rules(context, record, errors)
        validation_rules.each do |rule|
          next unless rule[:on] == context
          next unless rule_condition_matches?(rule, record)

          validate_rule(rule, record, errors)
        end
      end

      sig { params(rule: HakumiORM::Validation::RulePayload, record: HakumiORM::Validation::ValidatableInterface, errors: HakumiORM::Errors).void }
      def validate_rule(rule, record, errors)
        if rule[:kind] == :custom
          run_custom_validation(rule, record, errors)
          return
        end

        attribute = T.cast(rule[:attribute], Symbol)
        value = read_attribute(record, attribute)
        context = HakumiORM::Validation::RuleContext.new(
          attribute: attribute,
          value: value,
          errors: errors,
          record: T.cast(record, Object)
        )
        return if value.nil? && T.cast(rule[:allow_nil], T::Boolean)
        return if context.blank_value? && T.cast(rule[:allow_blank], T::Boolean)

        kind = T.cast(rule[:kind], Symbol)
        validator = HakumiORM::Validation::Validators::Registry.fetch(kind)
        validator.validate(context, rule)
      end

      sig { params(record: HakumiORM::Validation::ValidatableInterface, attribute: Symbol).returns(Object) }
      def read_attribute(record, attribute)
        record.validation_value(attribute)
      end

      sig { params(rule: HakumiORM::Validation::RulePayload, record: HakumiORM::Validation::ValidatableInterface).returns(T::Boolean) }
      def rule_condition_matches?(rule, record)
        if_cond = rule[:if]
        unless_cond = rule[:unless]
        return false if if_cond && !resolve_condition(if_cond, record)
        return false if unless_cond && resolve_condition(unless_cond, record)

        true
      end

      sig { params(raw_condition: Object, record: HakumiORM::Validation::ValidatableInterface).returns(T::Boolean) }
      def resolve_condition(raw_condition, record)
        return T.cast(raw_condition, T::Boolean) if [true, false].include?(raw_condition)

        if raw_condition.is_a?(Symbol)
          value = record.validation_value(raw_condition)
          return T.cast(value, T::Boolean) if [true, false].include?(value)

          raise ArgumentError, "validation condition symbol must resolve to true/false"
        end

        return call_proc_condition(raw_condition, record) if raw_condition.is_a?(Proc)

        raise ArgumentError, "validation condition must be Symbol, Proc or Boolean"
      end

      sig { params(callable: Proc, record: HakumiORM::Validation::ValidatableInterface).returns(T::Boolean) }
      def call_proc_condition(callable, record)
        value = callable.arity.zero? ? callable.call : callable.call(record)
        return value if [true, false].include?(value)

        raise ArgumentError, "validation condition proc must return true/false"
      end
    end
  end
end
