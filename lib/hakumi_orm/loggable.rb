# typed: strict
# frozen_string_literal: true

module HakumiORM
  # Sorbet interface for loggers. Any object implementing these five methods
  # can be assigned to `HakumiORM.config.logger`. `::Logger` includes this
  # module at boot so it satisfies the contract out of the box.
  module Loggable
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.params(message: T.nilable(String), blk: T.nilable(T.proc.returns(String))).void }
    def debug(message = nil, &blk); end

    sig { abstract.params(message: T.nilable(String), blk: T.nilable(T.proc.returns(String))).void }
    def info(message = nil, &blk); end

    sig { abstract.params(message: T.nilable(String), blk: T.nilable(T.proc.returns(String))).void }
    def warn(message = nil, &blk); end

    sig { abstract.params(message: T.nilable(String), blk: T.nilable(T.proc.returns(String))).void }
    def error(message = nil, &blk); end

    sig { abstract.params(message: T.nilable(String), blk: T.nilable(T.proc.returns(String))).void }
    def fatal(message = nil, &blk); end
  end
end

require "logger"
Logger.include(HakumiORM::Loggable)
