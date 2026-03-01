# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Adapter
    # Infrastructure implementation of AdapterFactoryPort.
    class FactoryGateway
      include Ports::AdapterFactoryPort

      extend T::Sig

      sig { override.params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Adapter::Base) }
      def connect_postgresql(params)
        Adapter::Postgresql.connect(params)
      end

      sig { override.params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Adapter::Base) }
      def connect_mysql(params)
        Adapter::Mysql.connect(params)
      end

      sig { override.params(database: String).returns(Adapter::Base) }
      def connect_sqlite(database)
        Adapter::Sqlite.connect(database)
      end
    end
  end
end
