# typed: strict
# frozen_string_literal: true

module HakumiORM
  module Framework
    extend T::Sig

    @detectors = T.let({}, T::Hash[Symbol, Proc])
    @current = T.let(nil, T.nilable(Symbol))

    sig { params(name: Symbol, detector: T.proc.returns(T::Boolean)).void }
    def self.register(name, &detector)
      @detectors[name] = detector
    end

    sig { returns(Symbol) }
    def self.detect
      @detectors.each do |name, detector|
        return name if detector.call
      end
      :standalone
    end

    sig { returns(T.nilable(Symbol)) }
    def self.current
      @current
    end

    sig { params(name: Symbol).void }
    def self.current=(name)
      @current = name
    end

    sig { returns(T::Boolean) }
    def self.rails?
      @current == :rails
    end

    sig { returns(T::Boolean) }
    def self.sinatra?
      @current == :sinatra
    end

    sig { returns(T::Boolean) }
    def self.standalone?
      @current.nil? || @current == :standalone
    end

    sig { returns(T::Array[Symbol]) }
    def self.registered
      @detectors.keys
    end

    sig { void }
    def self.reset!
      @current = nil
      @detectors.clear
    end
  end
end
