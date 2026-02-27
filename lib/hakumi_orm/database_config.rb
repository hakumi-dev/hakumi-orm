# typed: strict
# frozen_string_literal: true

# Internal component for database_config.
module HakumiORM
  # Internal class for HakumiORM.
  class DatabaseConfig < T::Struct
    const :adapter_name, Symbol
    const :database, String
    const :host, T.nilable(String), default: nil
    const :port, T.nilable(Integer), default: nil
    const :username, T.nilable(String), default: nil
    const :password, T.nilable(String), default: nil
    const :pool_size, Integer, default: 5
    const :pool_timeout, Float, default: 5.0
    const :connection_options, T::Hash[String, String], default: {}
  end
end
