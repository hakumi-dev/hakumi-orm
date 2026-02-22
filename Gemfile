# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "bigdecimal", require: false
gem "irb", require: false
gem "minitest", "~> 5.16", require: false
gem "rake", "~> 13.0", require: false
gem "rubocop", "~> 1.21", require: false
gem "rubocop-minitest", require: false

# Database drivers (optional at runtime, needed for tests/codegen)
gem "mysql2", require: false
gem "pg", require: false
gem "sqlite3", require: false

# Sorbet static analysis
gem "sorbet", require: false
gem "tapioca", ">= 0.17", require: false

# Benchmarking (sandbox only)
gem "activerecord", require: false
gem "benchmark-ips", require: false

gem "mdl", require: false
gem "rubocop-performance", "~> 1.26", group: :development
gem "rubocop-sorbet", "~> 0.12.0", group: :development
