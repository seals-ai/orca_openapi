# frozen_string_literal: true

require 'spec_helper'
require 'orca_openapi/schema' # For backward-compat test

module StructExtensionTestFixtures
  class BasicSchema < T::Struct
    const :name, String, description: "User's full name"
    const :age, Integer
  end

  class WithFormats < T::Struct
    const :id, String, description: 'Unique identifier', format: 'uuid'
    const :created_at, String, description: 'Creation timestamp', format: 'date-time'
    const :score, Float, description: 'Score value', example: 99.5
  end

  class WithNilables < T::Struct
    const :required_field, String
    const :optional_field, T.nilable(String)
    const :optional_number, T.nilable(Integer), description: 'An optional count'
  end

  class WithDefaults < T::Struct
    const :name, String
    const :role, String, default: 'member'
  end

  class NestedItem < T::Struct
    const :id, String
    const :value, Float
  end

  class WithNestedArray < T::Struct
    const :items, T::Array[NestedItem], description: 'List of items'
    const :count, Integer
  end

  class EmptySchema < T::Struct
  end

  class AllOptional < T::Struct
    const :a, T.nilable(String)
    const :b, T.nilable(Integer)
  end
end

RSpec.describe OrcaOpenAPI::StructExtension do
  describe '.field_metadata' do
    it 'is available on any T::Struct subclass without include' do
      expect(StructExtensionTestFixtures::BasicSchema).to respond_to(:field_metadata)
    end

    it 'stores description for fields that have one' do
      meta = StructExtensionTestFixtures::BasicSchema.field_metadata
      expect(meta[:name][:description]).to eq("User's full name")
    end

    it 'does not store metadata for fields without any' do
      meta = StructExtensionTestFixtures::BasicSchema.field_metadata
      expect(meta).not_to have_key(:age)
    end

    it 'stores format overrides' do
      meta = StructExtensionTestFixtures::WithFormats.field_metadata
      expect(meta[:id][:format]).to eq('uuid')
      expect(meta[:created_at][:format]).to eq('date-time')
    end

    it 'stores example values' do
      meta = StructExtensionTestFixtures::WithFormats.field_metadata
      expect(meta[:score][:example]).to eq(99.5)
    end

    it 'stores description on nilable fields' do
      meta = StructExtensionTestFixtures::WithNilables.field_metadata
      expect(meta[:optional_number][:description]).to eq('An optional count')
    end

    it 'returns empty hash when no fields have metadata' do
      expect(StructExtensionTestFixtures::EmptySchema.field_metadata).to eq({})
    end
  end

  describe '.openapi_name' do
    it 'is available on any T::Struct subclass without include' do
      expect(StructExtensionTestFixtures::BasicSchema).to respond_to(:openapi_name)
    end

    it 'converts class name to snake_case with underscores' do
      expect(StructExtensionTestFixtures::BasicSchema.openapi_name).to eq(
        'struct_extension_test_fixtures_basic_schema'
      )
    end

    it 'handles deeply nested namespaces' do
      expect(StructExtensionTestFixtures::WithNestedArray.openapi_name).to eq(
        'struct_extension_test_fixtures_with_nested_array'
      )
    end
  end

  describe 'backward compatibility' do
    it 'OrcaOpenAPI::Schema include is a silent no-op' do
      # Ensure including the deprecated module does not raise
      expect do
        Class.new(T::Struct) do
          include OrcaOpenAPI::Schema
        end
      end.not_to raise_error
    end
  end

  # Schema generation is now handled by Generator#struct_to_openapi_schema.
  # These tests verify the Generator correctly reads field_metadata from any T::Struct.
  describe 'schema generation via Generator' do
    # Helper: use the Generator's struct_to_openapi_schema method.
    # We instantiate a Generator and call the private method directly for unit testing.
    def generate_schema(klass)
      generator = OrcaOpenAPI::Generator.new(configuration: OrcaOpenAPI::Configuration.new, routes: [])
      generator.send(:struct_to_openapi_schema, klass)
    end

    it 'generates object schema with properties' do
      schema = generate_schema(StructExtensionTestFixtures::BasicSchema)

      expect(schema[:type]).to eq('object')
      expect(schema[:properties]).to have_key(:name)
      expect(schema[:properties]).to have_key(:age)
    end

    it 'includes description from field_metadata' do
      schema = generate_schema(StructExtensionTestFixtures::BasicSchema)

      expect(schema[:properties][:name][:description]).to eq("User's full name")
    end

    it 'does not include description when not provided' do
      schema = generate_schema(StructExtensionTestFixtures::BasicSchema)

      expect(schema[:properties][:age]).not_to have_key(:description)
    end

    it 'overrides format from metadata' do
      schema = generate_schema(StructExtensionTestFixtures::WithFormats)

      expect(schema[:properties][:id][:format]).to eq('uuid')
      expect(schema[:properties][:id][:type]).to eq('string')
    end

    it 'includes example from metadata' do
      schema = generate_schema(StructExtensionTestFixtures::WithFormats)

      expect(schema[:properties][:score][:example]).to eq(99.5)
    end

    context 'with required fields' do
      it 'lists non-nilable fields without defaults as required' do
        schema = generate_schema(StructExtensionTestFixtures::BasicSchema)

        expect(schema[:required]).to contain_exactly('name', 'age')
      end

      it 'excludes nilable fields from required' do
        schema = generate_schema(StructExtensionTestFixtures::WithNilables)

        expect(schema[:required]).to eq(['required_field'])
      end

      it 'excludes fields with defaults from required' do
        schema = generate_schema(StructExtensionTestFixtures::WithDefaults)

        expect(schema[:required]).to eq(['name'])
      end

      it 'omits required key when all fields are optional' do
        schema = generate_schema(StructExtensionTestFixtures::AllOptional)

        expect(schema).not_to have_key(:required)
      end
    end

    context 'with nilable types' do
      it 'uses OAS 3.1 type array for nilable primitives' do
        schema = generate_schema(StructExtensionTestFixtures::WithNilables)

        expect(schema[:properties][:optional_field][:type]).to eq(%w[string null])
      end

      it 'preserves description on nilable fields' do
        schema = generate_schema(StructExtensionTestFixtures::WithNilables)

        expect(schema[:properties][:optional_number][:description]).to eq('An optional count')
      end
    end

    context 'with nested schemas' do
      it 'uses $ref for nested schema types in arrays' do
        schema = generate_schema(StructExtensionTestFixtures::WithNestedArray)
        items_prop = schema[:properties][:items]

        expect(items_prop[:type]).to eq('array')
        expect(items_prop[:items]['$ref']).to match(%r{#/components/schemas/.*nested_item})
      end

      it 'preserves description on array fields' do
        schema = generate_schema(StructExtensionTestFixtures::WithNestedArray)

        expect(schema[:properties][:items][:description]).to eq('List of items')
      end
    end

    context 'with empty schema' do
      it 'returns object type with empty properties' do
        schema = generate_schema(StructExtensionTestFixtures::EmptySchema)

        expect(schema[:type]).to eq('object')
        expect(schema[:properties]).to eq({})
        expect(schema).not_to have_key(:required)
      end
    end

    context 'with auto-inferred formats' do
      it 'auto-infers int64 format for Integer fields' do
        schema = generate_schema(StructExtensionTestFixtures::BasicSchema)

        expect(schema[:properties][:age][:format]).to eq('int64')
      end

      it 'auto-infers float format for Float fields' do
        schema = generate_schema(StructExtensionTestFixtures::NestedItem)

        expect(schema[:properties][:value][:format]).to eq('float')
      end

      it 'allows metadata format to override auto-inferred format' do
        schema = generate_schema(StructExtensionTestFixtures::WithFormats)

        # id is String with explicit format: 'uuid' — should not be overridden
        expect(schema[:properties][:id][:format]).to eq('uuid')
      end
    end
  end
end
