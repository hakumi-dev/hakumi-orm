# typed: strict
# frozen_string_literal: true

require "rake/task"

# Temporary compatibility layer for Rails apps that still call hakumi:* tasks
# while the canonical task namespace is db:*.
# Keep this isolated from core task definitions and remove once demo and
# benchmark projects stop depending on hakumi:*.

module HakumiORM
  # Registers legacy task aliases without affecting canonical tasks.
  module TasksCompat
    extend T::Sig

    module_function

    sig { void }
    def define!
      %i[install generate migrate version check seed].each { |name| define_simple_alias(name) }
      define_arg_alias(name: :type, arg: :name)
      define_arg_alias(name: :rollback, arg: :count)
      define_arg_alias(name: :migration, arg: :name)
      define_arg_alias(name: :associations, arg: :table)
      define_arg_alias(name: :scaffold, arg: :table)
      define_simple_alias(:prepare)
      define_namespaced_alias(from: "hakumi:migrate:status", target_task: "db:migrate:status")
      define_namespaced_alias(from: "hakumi:fixtures:load", target_task: "db:fixtures:load")
    end

    sig { params(name: Symbol).void }
    def define_simple_alias(name)
      alias_name = "hakumi:#{name}"
      return if Rake::Task.task_defined?(alias_name)

      Rake::Task.define_task(alias_name) { Rake::Task["db:#{name}"].invoke }
    end

    sig { params(name: Symbol, arg: Symbol).void }
    def define_arg_alias(name:, arg:)
      alias_name = "hakumi:#{name}"
      return if Rake::Task.task_defined?(alias_name)

      Rake::Task.define_task(alias_name, [arg]) do |_task, args|
        value = args[arg]
        Rake::Task["db:#{name}"].invoke(value)
      end
    end

    sig { params(from: String, target_task: String).void }
    def define_namespaced_alias(from:, target_task:)
      return if Rake::Task.task_defined?(from)

      Rake::Task.define_task(from) { Rake::Task[target_task].invoke }
    end
  end
end
