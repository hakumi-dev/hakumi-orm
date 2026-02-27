# typed: strict
# frozen_string_literal: true

require "uri"

# Internal component for database_url_parser.
module HakumiORM
  # Internal class for HakumiORM.
  class DatabaseUrlParser
    extend T::Sig

    SCHEME_MAP = T.let({
      "postgresql" => :postgresql,
      "postgres" => :postgresql,
      "mysql2" => :mysql,
      "mysql" => :mysql,
      "sqlite3" => :sqlite,
      "sqlite" => :sqlite
    }.freeze, T::Hash[String, Symbol])

    sig { params(url: String).returns(DatabaseConfig) }
    def self.parse(url)
      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        raise HakumiORM::Error, "Invalid database_url: #{url.inspect}"
      end

      scheme = uri.scheme
      raise HakumiORM::Error, "Invalid database_url: missing scheme in #{url.inspect}" unless scheme

      adapter_name = SCHEME_MAP[scheme]
      raise HakumiORM::Error, "Unsupported database_url scheme: #{scheme.inspect}" unless adapter_name

      database = extract_database(uri, adapter_name)
      options = extract_query_options(uri)

      DatabaseConfig.new(
        adapter_name: adapter_name,
        database: database,
        host: empty_to_nil(uri.host),
        port: uri.port,
        username: empty_to_nil(uri.user),
        password: decode_password(uri.password),
        connection_options: options
      )
    end

    sig { params(uri: URI::Generic, adapter_name: Symbol).returns(String) }
    private_class_method def self.extract_database(uri, adapter_name)
      path = uri.path || ""

      if adapter_name == :sqlite
        path = path.delete_prefix("/") if path.start_with?("//")
        raise HakumiORM::Error, "Invalid database_url: missing database path" if path.empty?

        path
      else
        db = path.delete_prefix("/")
        raise HakumiORM::Error, "Invalid database_url: missing database name" if db.empty?

        db
      end
    end

    sig { params(uri: URI::Generic).returns(T::Hash[String, String]) }
    private_class_method def self.extract_query_options(uri)
      query = uri.query
      return {} unless query

      URI.decode_www_form(query).to_h
    end

    sig { params(raw: T.nilable(String)).returns(T.nilable(String)) }
    private_class_method def self.decode_password(raw)
      return nil unless raw

      URI.decode_www_form_component(raw)
    end

    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    private_class_method def self.empty_to_nil(value)
      return nil if value.nil? || value.empty?

      value
    end
  end
end
