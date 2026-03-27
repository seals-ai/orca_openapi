# frozen_string_literal: true

module OrcaOpenAPI
  # Validates a parsed request body hash against T::Struct schema(s).
  #
  # Supports two modes:
  #   1. Single schema — instantiates the struct; raises ValidationError on failure.
  #   2. Array of schemas (oneOf) — tries each variant in order; returns the first
  #      successful match. T::Struct's strict key checking acts as a natural
  #      discriminator: only the variant whose field set matches will succeed.
  #
  # @example Single schema
  #   ParamValidator.call({ name: 'Widget', quantity: 5 }, CreateRequest)
  #   # => #<CreateRequest name="Widget" quantity=5>
  #
  # @example Array (oneOf)
  #   ParamValidator.call({ customer_id: 'abc', product_ids: ['p1'] },
  #                       [PricesByCustomer, PricesByOrganization, PricesByPerson])
  #   # => #<PricesByCustomer customer_id="abc" product_ids=["p1"]>
  #
  class ParamValidator
    class << self
      # @param body_hash [Hash{Symbol => Object}] Parsed request body (symbolized keys)
      # @param schema [Class<T::Struct>, Array<Class<T::Struct>>] Schema(s) to validate against
      # @return [T::Struct] Validated struct instance
      # @raise [OrcaOpenAPI::ValidationError] When validation fails
      def call(body_hash, schema)
        if schema.is_a?(Array)
          validate_one_of(body_hash, schema)
        else
          validate_single(body_hash, schema)
        end
      end

      private

      def validate_single(body_hash, klass)
        klass.new(**body_hash)
      rescue ArgumentError, TypeError => e
        raise ValidationError.new("Invalid request body: #{e.message}")
      end

      def validate_one_of(body_hash, schemas)
        errors = []

        schemas.each do |klass|
          return klass.new(**body_hash)
        rescue ArgumentError, TypeError => e
          errors << "#{klass.name}: #{e.message}"
        end

        raise ValidationError.new(
          'Request body does not match any accepted format',
          details: errors
        )
      end
    end
  end
end
