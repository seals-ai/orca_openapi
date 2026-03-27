# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

require_relative 'orca_openapi/version'
require_relative 'orca_openapi/struct_extension'
require_relative 'orca_openapi/validation_error'
require_relative 'orca_openapi/param_validator'
require_relative 'orca_openapi/type_converter'
require_relative 'orca_openapi/controller'
require_relative 'orca_openapi/configuration'
require_relative 'orca_openapi/generator'

module OrcaOpenAPI
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    # Returns true once configure has been called (i.e., a Configuration exists).
    # Used by Controller.included to decide whether to auto-register.
    def configured?
      !@configuration.nil?
    end

    def configure
      yield(configuration)
    end

    # Resets configuration (useful in tests).
    def reset!
      @configuration = Configuration.new
    end

    # Shortcut to generate the spec.
    def generate
      Generator.new.generate
    end

    # Shortcut to generate and write to file.
    def generate!
      Generator.new.generate_to_file
    end
  end
end
