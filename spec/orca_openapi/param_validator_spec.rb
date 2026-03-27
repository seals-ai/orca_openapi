# frozen_string_literal: true

require 'spec_helper'

# -- Fixture schemas for ParamValidator tests --

module ParamValidatorFixtures
  class SimpleRequest < T::Struct
    const :name, String
    const :quantity, Integer
  end

  class OptionalFieldRequest < T::Struct
    const :name, String
    const :note, T.nilable(String)
  end

  class VariantCustomer < T::Struct
    const :customer_id, String
    const :product_ids, T::Array[String]
  end

  class VariantOrganization < T::Struct
    const :organization_id, String
    const :product_ids, T::Array[String]
  end

  class VariantPerson < T::Struct
    const :person_id, String
    const :product_ids, T::Array[String]
  end
end

RSpec.describe OrcaOpenAPI::ParamValidator do
  describe '.call with single schema' do
    it 'returns a struct instance when all fields are valid' do
      result = described_class.call(
        { name: 'Widget', quantity: 5 },
        ParamValidatorFixtures::SimpleRequest
      )

      expect(result).to be_a(ParamValidatorFixtures::SimpleRequest)
      expect(result.name).to eq('Widget')
      expect(result.quantity).to eq(5)
    end

    it 'accepts optional fields as nil' do
      result = described_class.call(
        { name: 'Widget' },
        ParamValidatorFixtures::OptionalFieldRequest
      )

      expect(result).to be_a(ParamValidatorFixtures::OptionalFieldRequest)
      expect(result.name).to eq('Widget')
      expect(result.note).to be_nil
    end

    it 'raises ValidationError when a required field is missing' do
      expect do
        described_class.call({ name: 'Widget' }, ParamValidatorFixtures::SimpleRequest)
      end.to raise_error(OrcaOpenAPI::ValidationError, /Invalid request body/)
    end

    it 'raises ValidationError when an unknown field is present' do
      expect do
        described_class.call(
          { name: 'Widget', quantity: 5, extra: 'nope' },
          ParamValidatorFixtures::SimpleRequest
        )
      end.to raise_error(OrcaOpenAPI::ValidationError, /Invalid request body/)
    end

    it 'raises ValidationError when a field has the wrong type' do
      expect do
        described_class.call(
          { name: 'Widget', quantity: 'not_a_number' },
          ParamValidatorFixtures::SimpleRequest
        )
      end.to raise_error(OrcaOpenAPI::ValidationError, /Invalid request body/)
    end
  end

  describe '.call with array schema (oneOf)' do
    let(:schemas) do
      [
        ParamValidatorFixtures::VariantCustomer,
        ParamValidatorFixtures::VariantOrganization,
        ParamValidatorFixtures::VariantPerson
      ]
    end

    it 'matches the first variant when its fields are present' do
      result = described_class.call(
        { customer_id: 'abc', product_ids: %w[p1 p2] },
        schemas
      )

      expect(result).to be_a(ParamValidatorFixtures::VariantCustomer)
      expect(result.customer_id).to eq('abc')
      expect(result.product_ids).to eq(%w[p1 p2])
    end

    it 'matches the second variant when its fields are present' do
      result = described_class.call(
        { organization_id: 'org-1', product_ids: %w[p1] },
        schemas
      )

      expect(result).to be_a(ParamValidatorFixtures::VariantOrganization)
      expect(result.organization_id).to eq('org-1')
    end

    it 'matches the third variant when its fields are present' do
      result = described_class.call(
        { person_id: 'per-1', product_ids: %w[p1] },
        schemas
      )

      expect(result).to be_a(ParamValidatorFixtures::VariantPerson)
      expect(result.person_id).to eq('per-1')
    end

    it 'raises ValidationError when no variant matches' do
      expect do
        described_class.call({ unknown_id: 'x', product_ids: %w[p1] }, schemas)
      end.to raise_error(OrcaOpenAPI::ValidationError, /does not match any accepted format/)
    end

    it 'includes per-variant error details when no variant matches' do
      error = nil
      begin
        described_class.call({ unknown_id: 'x', product_ids: %w[p1] }, schemas)
      rescue OrcaOpenAPI::ValidationError => e
        error = e
      end

      expect(error.details).to be_an(Array)
      expect(error.details.length).to eq(3)
      expect(error.details[0]).to include('VariantCustomer')
      expect(error.details[1]).to include('VariantOrganization')
      expect(error.details[2]).to include('VariantPerson')
    end

    it 'rejects requests with fields from multiple variants' do
      # customer_id + organization_id — neither variant accepts both
      expect do
        described_class.call(
          { customer_id: 'abc', organization_id: 'org-1', product_ids: %w[p1] },
          schemas
        )
      end.to raise_error(OrcaOpenAPI::ValidationError, /does not match any accepted format/)
    end

    it 'raises ValidationError when body is empty hash' do
      expect do
        described_class.call({}, schemas)
      end.to raise_error(OrcaOpenAPI::ValidationError)
    end
  end
end
