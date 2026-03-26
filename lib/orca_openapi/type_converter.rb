# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Converts Sorbet type objects into OpenAPI 3.1 schema hashes.
  #
  # Handles:
  #   - Primitive types (String, Integer, Float, T::Boolean, NilClass)
  #   - Nilable types (T.nilable(X) → oneOf with null)
  #   - Arrays (T::Array[X] → { type: "array", items: ... })
  #   - Nested schemas (subclasses of OrcaOpenAPI::Schema → $ref)
  #   - Enums (T::Enum subclasses)
  #
  # OpenAPI 3.1 uses JSON Schema 2020-12, which supports `type: ["string", "null"]`
  # for nullable fields (no need for the OAS 3.0 `nullable: true` workaround).
  module TypeConverter
    PRIMITIVE_MAP = {
      'String' => { type: 'string' },
      'Integer' => { type: 'integer' },
      'Float' => { type: 'number', format: 'float' },
      'Numeric' => { type: 'number' },
      'TrueClass' => { type: 'boolean' },
      'FalseClass' => { type: 'boolean' },
      'NilClass' => { type: 'null' },
      'Date' => { type: 'string', format: 'date' },
      'Time' => { type: 'string', format: 'date-time' },
      'DateTime' => { type: 'string', format: 'date-time' },
      'Symbol' => { type: 'string' }
    }.freeze

    class << self
      # Converts a Sorbet type object to an OpenAPI 3.1 schema hash.
      #
      # @param sorbet_type [T::Types::Base, Class] The Sorbet type to convert
      # @return [Hash] OpenAPI 3.1 schema hash
      def convert(sorbet_type)
        case sorbet_type
        when T::Types::TypedArray
          convert_array(sorbet_type)
        when T::Types::Simple
          convert_simple(sorbet_type)
        when T::Types::Union
          convert_union(sorbet_type)
        when T::Types::TypedHash
          convert_hash(sorbet_type)
        when T::Types::ClassOf
          convert_class(sorbet_type.raw_type)
        when Class
          convert_class(sorbet_type)
        else
          # Fallback for unknown types
          { type: 'object' }
        end
      end

      private

      def convert_array(type)
        {
          type: 'array',
          items: convert(type.type)
        }
      end

      def convert_simple(type)
        convert_class(type.raw_type)
      end

      def convert_union(type)
        types = type.types

        # T.nilable(X) is represented as T::Union[X, NilClass]
        # In OpenAPI 3.1, use type: ["<type>", "null"] for simple nilables
        non_nil = types.reject { |t| nil_type?(t) }
        has_nil = types.any? { |t| nil_type?(t) }

        if has_nil && non_nil.size == 1
          convert_nilable(non_nil.first)
        else
          # General union → oneOf
          { oneOf: types.map { |t| convert(t) } }
        end
      end

      def convert_nilable(inner_type)
        inner = convert(inner_type)

        # For simple types, use type: ["<type>", "null"] (OAS 3.1 style)
        if inner[:type].is_a?(String) && !inner.key?(:oneOf) && !inner.key?(:$ref)
          inner.merge(type: [inner[:type], 'null'])
        else
          # For complex types ($ref, oneOf, etc.), wrap in oneOf
          { oneOf: [inner, { type: 'null' }] }
        end
      end

      def convert_hash(type)
        {
          type: 'object',
          additionalProperties: convert(type.values)
        }
      end

      def convert_class(klass)
        # Check for OrcaOpenAPI::Schema subclass → $ref
        if defined?(OrcaOpenAPI::Schema) && klass < OrcaOpenAPI::Schema
          { '$ref' => "#/components/schemas/#{schema_name(klass)}" }
        elsif klass.respond_to?(:values) && klass < T::Enum
          convert_enum(klass)
        else
          # Try primitive map — dup to avoid mutating frozen shared hashes
          PRIMITIVE_MAP.fetch(klass.name, { type: 'object' }).dup
        end
      end

      def convert_enum(klass)
        values = klass.values.map(&:serialize)
        { type: 'string', enum: values }
      end

      def nil_type?(type)
        case type
        when T::Types::Simple
          type.raw_type == NilClass
        when Class
          type == NilClass
        else
          false
        end
      end

      # Derives an OpenAPI schema name from a class.
      # Llm::V1::Products::PricesResponse → "llm_v1_products_prices_response"
      def schema_name(klass)
        klass.name.gsub('::', '_').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end
  end
end
