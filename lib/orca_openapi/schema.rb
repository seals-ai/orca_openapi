# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Mixin for T::Struct subclasses that adds OpenAPI metadata support.
  #
  # Sorbet's T::Struct rejects unknown keyword arguments on `const` / `prop`.
  # This module overrides `const` to capture metadata (description, format, example)
  # before forwarding valid kwargs to Sorbet.
  #
  # Include this module when you need to:
  #   - Add `description:`, `format:`, or `example:` metadata to const/prop fields
  #   - Override `to_openapi_schema` (e.g. for oneOf wrappers)
  #   - Provide `variant_schemas` for BFS schema collection
  #   - Override `openapi_name` for custom component naming
  #
  # Plain T::Struct subclasses (without this module) are also supported by the
  # Generator — they just won't carry field-level metadata.
  #
  # Usage:
  #   class ProductPrice < T::Struct
  #     include OrcaOpenAPI::Schema
  #
  #     const :id, String, description: 'Product UUID', format: 'uuid'
  #     const :price, T.nilable(Float), description: 'List price'
  #     const :name, String   # no metadata needed — works without kwargs
  #   end
  #
  module Schema
    # Metadata keys that OrcaOpenAPI captures from const/prop kwargs.
    METADATA_KEYS = %i[description format example].freeze

    def self.included(base)
      unless base < T::Struct
        raise ArgumentError, 'OrcaOpenAPI::Schema can only be included in T::Struct subclasses, ' \
                             "got #{base}"
      end

      base.extend(ClassMethods)
    end

    module ClassMethods
      # Override const to capture metadata before forwarding to Sorbet.
      # Sorbet rejects unknown kwargs, so we strip description/format/example
      # and store them separately in field_metadata.
      def const(name, type, **kwargs)
        meta = {}
        METADATA_KEYS.each do |key|
          meta[key] = kwargs.delete(key) if kwargs.key?(key)
        end
        field_metadata[name] = meta unless meta.empty?

        super(name, type, **kwargs)
      end

      # Returns the stored metadata for all fields.
      # @return [Hash{Symbol => Hash}] field_name => { description:, format:, example: }
      def field_metadata
        @field_metadata ||= {}
      end

      # Returns the OpenAPI component name for this schema.
      # Can be overridden for custom naming.
      #   Llm::V1::Products::PricesResponse → "llm_v1_products_prices_response"
      def openapi_name
        name.gsub('::', '_').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
