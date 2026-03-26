# frozen_string_literal: true

require 'spec_helper'

# -------------------------------------------------------------------
# End-to-end integration spec: models the real LLM prices endpoint
# from the Seals backend and verifies that OrcaOpenAPI produces an
# OpenAPI 3.1 spec equivalent to the existing rswag definition.
# -------------------------------------------------------------------

module PricesEndpointFixtures
  # -- Request schemas (oneOf pattern) --

  class PricesByCustomer < T::Struct
    include OrcaOpenAPI::Schema

    const :customer_id, String, description: 'Customer UUID', format: 'uuid'
    const :product_ids, T::Array[String], description: 'Product UUIDs'
  end

  class PricesByOrganization < T::Struct
    include OrcaOpenAPI::Schema

    const :organization_id, String, description: 'Organization UUID', format: 'uuid'
    const :product_ids, T::Array[String], description: 'Product UUIDs'
  end

  class PricesByPerson < T::Struct
    include OrcaOpenAPI::Schema

    const :person_id, String, description: 'Person UUID', format: 'uuid'
    const :product_ids, T::Array[String], description: 'Product UUIDs'
  end

  # Wrapper that aggregates the three variants into oneOf.
  # OrcaOpenAPI::Schema#to_openapi_schema is designed for object schemas,
  # so we manually define the oneOf envelope for now.
  # In a future version, the gem could support a `one_of` DSL directly.
  class PricesRequest < T::Struct
    include OrcaOpenAPI::Schema

    class << self
      def to_openapi_schema
        {
          oneOf: [
            { '$ref' => "#/components/schemas/#{PricesByCustomer.openapi_name}" },
            { '$ref' => "#/components/schemas/#{PricesByOrganization.openapi_name}" },
            { '$ref' => "#/components/schemas/#{PricesByPerson.openapi_name}" }
          ]
        }
      end

      # Expose the variant classes so the generator can collect them.
      def variant_schemas
        [PricesByCustomer, PricesByOrganization, PricesByPerson]
      end
    end
  end

  # -- Response schemas --

  class ProductPrice < T::Struct
    include OrcaOpenAPI::Schema

    const :id, String, description: 'Product UUID', format: 'uuid'
    const :price, T.nilable(Float), description: 'List price'
    const :price_cents, T.nilable(Integer), description: 'List price in cents'
    const :price_formatted, T.nilable(String), description: 'Formatted list price'
    const :price_currency, T.nilable(String), description: 'List price currency code'
    const :customer_price, T.nilable(Float), description: 'Customer-specific price'
    const :customer_price_cents, T.nilable(Integer), description: 'Customer price in cents'
    const :customer_price_formatted, T.nilable(String), description: 'Formatted customer price'
    const :customer_price_currency, T.nilable(String), description: 'Customer price currency code'
  end

  class PricesResponse < T::Struct
    include OrcaOpenAPI::Schema

    const :products, T::Array[ProductPrice], description: 'Product prices'
  end

  class ErrorResponse < T::Struct
    include OrcaOpenAPI::Schema

    const :error, String, description: 'Error message'
  end

  # -- Controller --

  class PricesController
    include OrcaOpenAPI::Controller

    tags 'Products'
    security :bearer

    typed_action :create,
                 summary: 'Ensure sync and return customer product prices',
                 params: PricesRequest,
                 headers: {
                   'X-Company-Id' => {
                     type: :string,
                     format: :uuid,
                     required: true,
                     description: 'Company UUID from auth context'
                   }
                 },
                 response: {
                   200 => PricesResponse,
                   401 => nil,
                   422 => ErrorResponse
                 }
  end
end

RSpec.describe 'Prices endpoint end-to-end' do
  subject(:spec) do
    OrcaOpenAPI::Generator.new(configuration: config, routes:).generate
  end

  let(:config) do
    OrcaOpenAPI::Configuration.new.tap do |c|
      c.title = 'LLM API'
      c.version = '1.0.0'
      c.server_url = 'https://api.hireseals.ai'
      c.security_scheme :bearer, type: :http, scheme: :bearer
      c.global_header 'X-Company-Id', type: :string, format: :uuid,
                                      required: true, description: 'Company UUID from auth context'
      c.register_controller(PricesEndpointFixtures::PricesController)
    end
  end

  let(:routes) do
    [
      {
        controller: 'prices_endpoint_fixtures/prices',
        action: :create,
        path: '/llm/products/prices',
        method: 'post',
        path_params: []
      }
    ]
  end

  describe 'top-level structure' do
    it 'produces a valid OpenAPI 3.1.0 document' do
      expect(spec['openapi']).to eq('3.1.0')
      expect(spec['info']['title']).to eq('LLM API')
      expect(spec['servers'].first['url']).to eq('https://api.hireseals.ai')
    end
  end

  describe 'paths' do
    let(:operation) { spec['paths']['/llm/products/prices']['post'] }

    it 'generates the prices endpoint path' do
      expect(spec['paths']).to have_key('/llm/products/prices')
    end

    it 'uses POST method' do
      expect(spec['paths']['/llm/products/prices']).to have_key('post')
    end

    it 'includes summary' do
      expect(operation['summary']).to eq('Ensure sync and return customer product prices')
    end

    it 'tags as Products' do
      expect(operation['tags']).to eq(['Products'])
    end

    it 'requires bearer security' do
      expect(operation['security']).to eq([{ 'bearer' => [] }])
    end

    describe 'parameters' do
      let(:params) { operation['parameters'] }

      it 'includes X-Company-Id as global header' do
        global_header = params.find do |p|
          p['name'] == 'X-Company-Id' && p['description'] == 'Company UUID from auth context'
        end
        expect(global_header).not_to be_nil
        expect(global_header['in']).to eq('header')
        expect(global_header['required']).to be true
        expect(global_header['schema']['type']).to eq('string')
        expect(global_header['schema']['format']).to eq('uuid')
      end
    end

    describe 'request body' do
      let(:request_body) { operation['requestBody'] }

      it 'is required' do
        expect(request_body['required']).to be true
      end

      it 'references the PricesRequest schema' do
        ref = request_body['content']['application/json']['schema']['$ref']
        expect(ref).to eq(
          "#/components/schemas/#{PricesEndpointFixtures::PricesRequest.openapi_name}"
        )
      end
    end

    describe 'responses' do
      let(:responses) { operation['responses'] }

      it 'defines 200, 401, and 422 status codes' do
        expect(responses.keys).to contain_exactly('200', '401', '422')
      end

      it '200 references PricesResponse schema' do
        ref = responses['200']['content']['application/json']['schema']['$ref']
        expect(ref).to eq(
          "#/components/schemas/#{PricesEndpointFixtures::PricesResponse.openapi_name}"
        )
      end

      it '200 has correct description' do
        expect(responses['200']['description']).to eq('Successful response')
      end

      it '401 has no content (no schema provided)' do
        expect(responses['401']).not_to have_key('content')
      end

      it '401 has correct description' do
        expect(responses['401']['description']).to eq('Unauthorized')
      end

      it '422 references ErrorResponse schema' do
        ref = responses['422']['content']['application/json']['schema']['$ref']
        expect(ref).to eq(
          "#/components/schemas/#{PricesEndpointFixtures::ErrorResponse.openapi_name}"
        )
      end
    end
  end

  describe 'components' do
    let(:schemas) { spec['components']['schemas'] }

    it 'includes the PricesRequest schema with oneOf' do
      request_schema = schemas[PricesEndpointFixtures::PricesRequest.openapi_name]
      expect(request_schema).to have_key(:oneOf)
      expect(request_schema[:oneOf].length).to eq(3)
    end

    it 'includes all three request variant schemas' do
      variant_names = [
        PricesEndpointFixtures::PricesByCustomer.openapi_name,
        PricesEndpointFixtures::PricesByOrganization.openapi_name,
        PricesEndpointFixtures::PricesByPerson.openapi_name
      ]

      variant_names.each do |name|
        expect(schemas).to have_key(name), "Expected schema '#{name}' to be in components"
      end
    end

    describe 'PricesByCustomer variant' do
      let(:variant) { schemas[PricesEndpointFixtures::PricesByCustomer.openapi_name] }

      it 'has customer_id as required string with uuid format' do
        expect(variant[:properties][:customer_id][:type]).to eq('string')
        expect(variant[:properties][:customer_id][:format]).to eq('uuid')
        expect(variant[:required]).to include('customer_id')
      end

      it 'has product_ids as required array of strings' do
        expect(variant[:properties][:product_ids][:type]).to eq('array')
        expect(variant[:properties][:product_ids][:items][:type]).to eq('string')
        expect(variant[:required]).to include('product_ids')
      end
    end

    describe 'PricesByOrganization variant' do
      let(:variant) { schemas[PricesEndpointFixtures::PricesByOrganization.openapi_name] }

      it 'has organization_id with uuid format' do
        expect(variant[:properties][:organization_id][:format]).to eq('uuid')
      end
    end

    describe 'PricesByPerson variant' do
      let(:variant) { schemas[PricesEndpointFixtures::PricesByPerson.openapi_name] }

      it 'has person_id with uuid format' do
        expect(variant[:properties][:person_id][:format]).to eq('uuid')
      end
    end

    describe 'PricesResponse schema' do
      let(:response_schema) { schemas[PricesEndpointFixtures::PricesResponse.openapi_name] }

      it 'has products as required array' do
        expect(response_schema[:properties][:products][:type]).to eq('array')
        expect(response_schema[:required]).to include('products')
      end

      it 'references ProductPrice schema in array items' do
        items_ref = response_schema[:properties][:products][:items]['$ref']
        expect(items_ref).to eq(
          "#/components/schemas/#{PricesEndpointFixtures::ProductPrice.openapi_name}"
        )
      end
    end

    describe 'ProductPrice schema' do
      let(:product_price) { schemas[PricesEndpointFixtures::ProductPrice.openapi_name] }

      it 'includes all expected properties' do
        expected_props = %i[
          id price price_cents price_formatted price_currency
          customer_price customer_price_cents customer_price_formatted customer_price_currency
        ]

        expected_props.each do |prop|
          expect(product_price[:properties]).to have_key(prop),
                                                "Expected property :#{prop} in ProductPrice"
        end
      end

      it 'marks only id as required (all others are nilable)' do
        expect(product_price[:required]).to eq(['id'])
      end

      it 'uses OAS 3.1 nullable type arrays for nilable fields' do
        expect(product_price[:properties][:price][:type]).to eq(%w[number null])
        expect(product_price[:properties][:price_cents][:type]).to eq(%w[integer null])
        expect(product_price[:properties][:price_formatted][:type]).to eq(%w[string null])
      end

      it 'includes uuid format on id field' do
        expect(product_price[:properties][:id][:format]).to eq('uuid')
      end
    end

    describe 'ErrorResponse schema' do
      let(:error_schema) { schemas[PricesEndpointFixtures::ErrorResponse.openapi_name] }

      it 'has error as required string' do
        expect(error_schema[:properties][:error][:type]).to eq('string')
        expect(error_schema[:required]).to include('error')
      end
    end

    describe 'security schemes' do
      it 'includes bearer scheme' do
        scheme = spec['components']['securitySchemes']['bearer']
        expect(scheme['type']).to eq('http')
        expect(scheme['scheme']).to eq('bearer')
      end
    end
  end

  describe 'JSON output' do
    it 'produces valid JSON that can be round-tripped' do
      require 'json'
      json_str = JSON.pretty_generate(spec)
      parsed = JSON.parse(json_str)

      expect(parsed['openapi']).to eq('3.1.0')
      expect(parsed['paths']).to have_key('/llm/products/prices')
    end
  end
end
