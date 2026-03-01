# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Ports
    # Port for creating concrete DB adapters from normalized params.
    module AdapterFactoryPort
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Adapter::Base) }
      def connect_postgresql(params); end

      sig { abstract.params(params: T::Hash[Symbol, T.any(String, Integer)]).returns(Adapter::Base) }
      def connect_mysql(params); end

      sig { abstract.params(database: String).returns(Adapter::Base) }
      def connect_sqlite(database); end
    end
  end
end
