# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Mixin for T::Struct subclasses that adds OpenAPI metadata and schema generation.
  #
  # Schemas define the shape of request and response bodies using Sorbet types.
  # Each field can carry a `description` that appears in the generated OpenAPI spec.
  #
  # Usage:
  #   class PricesRequest < T::Struct
  #     include OrcaOpenAPI::Schema
  #
  #     const :customer_id, T.nilable(String), description: "Customer UUID"
  #     const :product_ids, T::Array[String], description: "Product UUIDs"
  #   end
  #
  # Then:
  #   PricesRequest.to_openapi_schema
  #   # => { type: "object", required: ["product_ids"], properties: { ... } }
  #
  module Schema
    def self.included(base)
      unless base < T::Struct
        raise ArgumentError, 'OrcaOpenAPI::Schema can only be included in T::Struct subclasses, ' \
                             "got #{base}"
      end

      base.extend(ClassMethods)
    end

    module ClassMethods
      # Override const to capture description metadata alongside Sorbet's prop definition.
      def const(name, type, description: nil, format: nil, example: nil, **kwargs)
        field_metadata[name] = { description:, format:, example: }
        super(name, type, **kwargs)
      end

      # Returns the stored metadata for all fields.
      def field_metadata
        @field_metadata ||= {}
      end

      # Generates an OpenAPI 3.1 schema hash for this struct.
      #
      # @return [Hash] OpenAPI schema object
      def to_openapi_schema
        props = {}
        required = []

        props_with_types.each do |prop_name, prop_info|
          type_object = prop_info[:type_object] || prop_info[:type]
          schema = TypeConverter.convert(type_object)

          # Merge field metadata (description, format override, example)
          meta = field_metadata[prop_name] || {}
          schema[:description] = meta[:description] if meta[:description]
          schema[:format] = meta[:format] if meta[:format]
          schema[:example] = meta[:example] unless meta[:example].nil?

          props[prop_name] = schema

          # A field is required if it's not nilable and has no default
          required << prop_name.to_s unless nilable_type?(type_object) || has_default?(prop_name)
        end

        result = { type: 'object', properties: props }
        result[:required] = required unless required.empty?
        result
      end

      # Returns the OpenAPI component name for this schema.
      # Llm::V1::Products::PricesResponse → "llm_v1_products_prices_response"
      def openapi_name
        name.gsub('::', '_').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      private

      # Access Sorbet's internal prop definitions.
      def props_with_types
        if respond_to?(:props, true)
          props
        else
          {}
        end
      end

      def nilable_type?(type)
        return false unless type.is_a?(T::Types::Union)

        type.types.any? { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
      end

      def has_default?(prop_name)
        prop_info = props[prop_name]
        return false unless prop_info

        prop_info.key?(:default)
      end
    end
  end
end
