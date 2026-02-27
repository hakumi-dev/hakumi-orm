# typed: false
# frozen_string_literal: true

# Temporary compatibility layer for Rails apps that still call `hakumi:*` tasks
# while the canonical task namespace is `db:*`.
# Keep this isolated (not in the core task definitions) and remove once the demo /
# benchmark apps and docs no longer depend on `hakumi:*`.

module HakumiORM
  module TasksCompat
    module_function

    def define!(tasks_mod)
      tasks_mod.instance_eval do
        namespace :hakumi do
          %i[install generate migrate version check seed].each do |name|
            safe_define_task("hakumi:#{name}") do
              task(name) { Rake::Task["db:#{name}"].invoke }
            end
          end

          { type: :name, rollback: :count, migration: :name, associations: :table, scaffold: :table }.each do |name, arg|
            safe_define_task("hakumi:#{name}") do
              task name, [arg] do |_t, args|
                Rake::Task["db:#{name}"].invoke(args[arg])
              end
            end
          end

          namespace :migrate do
            safe_define_task("hakumi:migrate:status") do
              task :status do
                Rake::Task["db:migrate:status"].invoke
              end
            end
          end
        end
      end
    end
  end
end
