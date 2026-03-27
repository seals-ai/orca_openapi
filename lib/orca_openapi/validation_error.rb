# frozen_string_literal: true

module OrcaOpenAPI
  # Raised when request body validation fails against the declared params schema.
  #
  # For single-schema validation, `message` describes the specific failure.
  # For oneOf (array params), `details` contains per-variant error messages.
  class ValidationError < StandardError
    attr_reader :details

    def initialize(message, details: nil)
      @details = details
      super(message)
    end
  end
end
