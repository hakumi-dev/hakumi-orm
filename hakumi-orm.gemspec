# frozen_string_literal: true

require_relative "lib/hakumi_orm/version"

Gem::Specification.new do |spec|
  spec.name = "hakumi-orm"
  spec.version = HakumiORM::VERSION
  spec.authors = ["kb714"]
  spec.email = ["aaguirre@buk.cl"]

  spec.summary = "Statically-typed, high-performance Ruby ORM engine"
  spec.description = "Hakumi ORM is a strictly-typed ORM engine for Ruby built on Sorbet. " \
                     "It generates fully typed models, query builders, and hydration code " \
                     "from your database schema with zero dynamic dispatch, zero method_missing, " \
                     "and zero T.untyped in the generated output. Designed for minimal allocations, " \
                     "low GC pressure, and YJIT-friendly execution."
  spec.homepage = "https://github.com/hakumi-dev/hakumi-orm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml sorbet/ AGENT.md])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "sorbet-runtime", ">= 0.5"
end
