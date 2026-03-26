# frozen_string_literal: true

require 'spec_helper'

module SchemaTestFixtures
  class BasicSchema < T::Struct
    include OrcaOpenAPI::Schema

    const :name, String, description: "User's full name"
    const :age, Integer
  end

  class WithFormats < T::Struct
    include OrcaOpenAPI::Schema

    const :id, String, description: 'Unique identifier', format: 'uuid'
    const :created_at, String, description: 'Creation timestamp', format: 'date-time'
    const :score, Float, description: 'Score value', example: 99.5
  end

  class WithNilables < T::Struct
    include OrcaOpenAPI::Schema

    const :required_field, String
    const :optional_field, T.nilable(String)
    const :optional_number, T.nilable(Integer), description: 'An optional count'
  end

  class WithDefaults < T::Struct
    include OrcaOpenAPI::Schema

    const :name, String
    const :role, String, default: 'member'
  end

  class NestedItem < T::Struct
    include OrcaOpenAPI::Schema

    const :id, String
    const :value, Float
  end

  class WithNestedArray < T::Struct
    include OrcaOpenAPI::Schema

    const :items, T::Array[NestedItem], description: 'List of items'
    const :count, Integer
  end

  class EmptySchema < T::Struct
    include OrcaOpenAPI::Schema
  end

  class AllOptional < T::Struct
    include OrcaOpenAPI::Schema

    const :a, T.nilable(String)
    const :b, T.nilable(Integer)
  end
end

RSpec.describe OrcaOpenAPI::Schema do
  describe '.included' do
    it 'raises ArgumentError when included in non-T::Struct class' do
      expect do
        Class.new do
          include OrcaOpenAPI::Schema
        end
      end.to raise_error(ArgumentError, /can only be included in T::Struct subclasses/)
    end
  end

  describe '.field_metadata' do
    it 'stores description for fields that have one' do
      meta = SchemaTestFixtures::BasicSchema.field_metadata
      expect(meta[:name][:description]).to eq("User's full name")
    end

    it 'stores nil description for fields without one' do
      meta = SchemaTestFixtures::BasicSchema.field_metadata
      expect(meta[:age][:description]).to be_nil
    end

    it 'stores format and example overrides' do
      meta = SchemaTestFixtures::WithFormats.field_metadata
      expect(meta[:id][:format]).to eq('uuid')
      expect(meta[:score][:example]).to eq(99.5)
    end
  end

  describe '.to_openapi_schema' do
    it 'generates object schema with properties' do
      schema = SchemaTestFixtures::BasicSchema.to_openapi_schema

      expect(schema[:type]).to eq('object')
      expect(schema[:properties]).to have_key(:name)
      expect(schema[:properties]).to have_key(:age)
    end

    it 'includes description in property schema' do
      schema = SchemaTestFixtures::BasicSchema.to_openapi_schema

      expect(schema[:properties][:name][:description]).to eq("User's full name")
    end

    it 'does not include description when not provided' do
      schema = SchemaTestFixtures::BasicSchema.to_openapi_schema

      expect(schema[:properties][:age]).not_to have_key(:description)
    end

    it 'overrides format from metadata' do
      schema = SchemaTestFixtures::WithFormats.to_openapi_schema

      expect(schema[:properties][:id][:format]).to eq('uuid')
      expect(schema[:properties][:id][:type]).to eq('string')
    end

    it 'includes example from metadata' do
      schema = SchemaTestFixtures::WithFormats.to_openapi_schema

      expect(schema[:properties][:score][:example]).to eq(99.5)
    end

    context 'with required fields' do
      it 'lists non-nilable fields without defaults as required' do
        schema = SchemaTestFixtures::BasicSchema.to_openapi_schema

        expect(schema[:required]).to contain_exactly('name', 'age')
      end

      it 'excludes nilable fields from required' do
        schema = SchemaTestFixtures::WithNilables.to_openapi_schema

        expect(schema[:required]).to eq(['required_field'])
      end

      it 'excludes fields with defaults from required' do
        schema = SchemaTestFixtures::WithDefaults.to_openapi_schema

        expect(schema[:required]).to eq(['name'])
      end

      it 'omits required key when all fields are optional' do
        schema = SchemaTestFixtures::AllOptional.to_openapi_schema

        expect(schema).not_to have_key(:required)
      end
    end

    context 'with nilable types' do
      it 'uses OAS 3.1 type array for nilable primitives' do
        schema = SchemaTestFixtures::WithNilables.to_openapi_schema

        expect(schema[:properties][:optional_field][:type]).to eq(%w[string null])
      end

      it 'preserves description on nilable fields' do
        schema = SchemaTestFixtures::WithNilables.to_openapi_schema

        expect(schema[:properties][:optional_number][:description]).to eq('An optional count')
      end
    end

    context 'with nested schemas' do
      it 'uses $ref for nested schema types in arrays' do
        schema = SchemaTestFixtures::WithNestedArray.to_openapi_schema
        items_prop = schema[:properties][:items]

        expect(items_prop[:type]).to eq('array')
        expect(items_prop[:items]['$ref']).to match(%r{#/components/schemas/.*nested_item})
      end

      it 'preserves description on array fields' do
        schema = SchemaTestFixtures::WithNestedArray.to_openapi_schema

        expect(schema[:properties][:items][:description]).to eq('List of items')
      end
    end

    context 'with empty schema' do
      it 'returns object type with empty properties' do
        schema = SchemaTestFixtures::EmptySchema.to_openapi_schema

        expect(schema[:type]).to eq('object')
        expect(schema[:properties]).to eq({})
        expect(schema).not_to have_key(:required)
      end
    end
  end

  describe '.openapi_name' do
    it 'converts class name to snake_case with underscores' do
      expect(SchemaTestFixtures::BasicSchema.openapi_name).to eq('schema_test_fixtures_basic_schema')
    end

    it 'handles deeply nested namespaces' do
      expect(SchemaTestFixtures::WithNestedArray.openapi_name).to eq(
        'schema_test_fixtures_with_nested_array'
      )
    end
  end
end
