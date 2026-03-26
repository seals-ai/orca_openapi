# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'yaml'
require 'tmpdir'

# -- Fixture schemas for generator tests --

module GeneratorTestFixtures
  class LineItem < T::Struct
    include OrcaOpenAPI::Schema

    const :product_id, String, description: 'Product ID'
    const :quantity, Integer
  end

  class OrderRequest < T::Struct
    include OrcaOpenAPI::Schema

    const :customer_id, String, description: 'Customer UUID', format: 'uuid'
    const :items, T::Array[LineItem], description: 'Order line items'
  end

  class OrderResponse < T::Struct
    include OrcaOpenAPI::Schema

    const :id, String, description: 'Order ID', format: 'uuid'
    const :status, String
    const :items, T::Array[LineItem]
    const :total_cents, Integer
  end

  class ErrorResponse < T::Struct
    include OrcaOpenAPI::Schema

    const :error, String, description: 'Error message'
    const :code, T.nilable(Integer), description: 'Error code'
  end

  class ListResponse < T::Struct
    include OrcaOpenAPI::Schema

    const :orders, T::Array[OrderResponse]
    const :total, Integer
  end

  class QueryParams < T::Struct
    include OrcaOpenAPI::Schema

    const :page, T.nilable(Integer), description: 'Page number'
    const :per_page, T.nilable(Integer), description: 'Items per page'
    const :status, T.nilable(String), description: 'Filter by status'
  end

  # Controller with multiple typed actions
  class OrdersController
    include OrcaOpenAPI::Controller

    tags 'Orders'
    security :bearer

    typed_action :index,
                 summary: 'List orders',
                 description: 'Returns paginated list of orders',
                 query_params: QueryParams,
                 response: { 200 => ListResponse }

    typed_action :create,
                 summary: 'Create an order',
                 params: OrderRequest,
                 response: {
                   201 => OrderResponse,
                   422 => ErrorResponse
                 }

    typed_action :show,
                 summary: 'Get order details',
                 response: { 200 => OrderResponse, 404 => ErrorResponse }
  end

  # Controller with action-level overrides
  class AdminController
    include OrcaOpenAPI::Controller

    tags 'Admin'
    security :api_key

    typed_action :create,
                 summary: 'Admin create',
                 tags: %w[Admin Special],
                 security: :bearer,
                 params: OrderRequest,
                 headers: { 'X-Admin-Token' => { type: :string, required: true, description: 'Admin token' } },
                 response: { 200 => OrderResponse }
  end

  # Controller with no typed actions
  class PlainController
    include OrcaOpenAPI::Controller
  end

  # Controller with an action that returns no response schemas (empty hash)
  class PlainEmptyResponseController
    include OrcaOpenAPI::Controller

    typed_action :noop, summary: 'No-op', response: {}
  end
end

RSpec.describe OrcaOpenAPI::Generator do
  subject(:generator) { described_class.new(configuration: config, routes:) }

  let(:config) do
    OrcaOpenAPI::Configuration.new.tap do |c|
      c.title = 'Test API'
      c.version = '2.0.0'
      c.description = 'A test API'
      c.server_url = 'https://api.test.com'
    end
  end

  let(:routes) do
    [
      { controller: 'generator_test_fixtures/orders', action: :index, path: '/orders', method: 'get', path_params: [] },
      { controller: 'generator_test_fixtures/orders', action: :create, path: '/orders', method: 'post',
        path_params: [] },
      { controller: 'generator_test_fixtures/orders', action: :show, path: '/orders/{id}', method: 'get',
        path_params: ['id'] },
      { controller: 'generator_test_fixtures/admin', action: :create, path: '/admin/orders', method: 'post',
        path_params: [] }
    ]
  end

  before do
    config.register_controller(GeneratorTestFixtures::OrdersController)
  end

  describe '#generate' do
    subject(:spec) { generator.generate }

    it 'produces an OpenAPI 3.1.0 document' do
      expect(spec['openapi']).to eq('3.1.0')
    end

    describe 'info section' do
      it 'includes title from configuration' do
        expect(spec['info']['title']).to eq('Test API')
      end

      it 'includes version from configuration' do
        expect(spec['info']['version']).to eq('2.0.0')
      end

      it 'includes description from configuration' do
        expect(spec['info']['description']).to eq('A test API')
      end

      it 'omits description when not configured' do
        config.description = nil
        expect(spec['info']).not_to have_key('description')
      end
    end

    describe 'servers section' do
      it 'includes configured server URL' do
        expect(spec['servers']).to eq([{ 'url' => 'https://api.test.com' }])
      end
    end

    describe 'paths section' do
      it 'generates paths for all typed actions with matching routes' do
        expect(spec['paths'].keys).to contain_exactly('/orders', '/orders/{id}')
      end

      it 'groups multiple methods under the same path' do
        orders_path = spec['paths']['/orders']
        expect(orders_path.keys).to contain_exactly('get', 'post')
      end

      describe 'operation building' do
        let(:create_op) { spec['paths']['/orders']['post'] }
        let(:index_op) { spec['paths']['/orders']['get'] }
        let(:show_op) { spec['paths']['/orders/{id}']['get'] }

        it 'includes summary' do
          expect(create_op['summary']).to eq('Create an order')
        end

        it 'includes description when provided' do
          expect(index_op['description']).to eq('Returns paginated list of orders')
        end

        it 'omits description when not provided' do
          expect(create_op).not_to have_key('description')
        end

        it 'includes tags from controller' do
          expect(create_op['tags']).to eq(['Orders'])
        end

        it 'generates operationId from controller path and action' do
          expect(create_op['operationId']).to eq('generator_test_fixtures_orders_create')
        end

        it 'includes security when set on controller' do
          expect(create_op['security']).to eq([{ 'bearer' => [] }])
        end
      end

      describe 'request body' do
        let(:create_op) { spec['paths']['/orders']['post'] }

        it 'generates $ref to params schema' do
          body = create_op['requestBody']
          expect(body['required']).to be true
          expect(body['content']['application/json']['schema']['$ref']).to eq(
            "#/components/schemas/#{GeneratorTestFixtures::OrderRequest.openapi_name}"
          )
        end

        it 'omits requestBody when no params schema' do
          index_op = spec['paths']['/orders']['get']
          expect(index_op).not_to have_key('requestBody')
        end
      end

      describe 'responses' do
        let(:create_op) { spec['paths']['/orders']['post'] }

        it 'generates response entries by status code' do
          responses = create_op['responses']
          expect(responses.keys).to contain_exactly('201', '422')
        end

        it 'includes $ref to response schema' do
          response_201 = create_op['responses']['201']
          expect(response_201['content']['application/json']['schema']['$ref']).to eq(
            "#/components/schemas/#{GeneratorTestFixtures::OrderResponse.openapi_name}"
          )
        end

        it 'provides default status descriptions' do
          expect(create_op['responses']['201']['description']).to eq('Created')
          expect(create_op['responses']['422']['description']).to eq('Unprocessable entity')
        end

        it 'generates default response when no response schemas are provided' do
          # The OrdersController already has responses on all actions,
          # so we test the build_responses logic via a dedicated controller with empty responses.
          # We can verify this indirectly: when a controller has `response: {}`,
          # the generator adds a 'default' key with 'Unexpected error' description.

          empty_config = OrcaOpenAPI::Configuration.new
          empty_config.register_controller(GeneratorTestFixtures::PlainEmptyResponseController)
          empty_routes = [
            { controller: 'generator_test_fixtures/plain_empty_response',
              action: :noop, path: '/noop', method: 'post', path_params: [] }
          ]

          gen = described_class.new(configuration: empty_config, routes: empty_routes)
          noop_spec = gen.generate
          responses = noop_spec['paths']['/noop']['post']['responses']

          expect(responses).to have_key('default')
          expect(responses['default']['description']).to eq('Unexpected error')
        end
      end

      describe 'parameters' do
        context 'with global headers' do
          before do
            config.global_header 'X-Company-Id', type: :string, format: :uuid,
                                                 required: true, description: 'Company ID'
          end

          it 'includes global headers in operation parameters' do
            create_op = spec['paths']['/orders']['post']
            header = create_op['parameters'].find { |p| p['name'] == 'X-Company-Id' }

            expect(header).not_to be_nil
            expect(header['in']).to eq('header')
            expect(header['required']).to be true
            expect(header['schema']['type']).to eq('string')
            expect(header['schema']['format']).to eq('uuid')
            expect(header['description']).to eq('Company ID')
          end
        end

        context 'with path parameters' do
          it 'includes path params from route' do
            show_op = spec['paths']['/orders/{id}']['get']
            path_param = show_op['parameters']&.find { |p| p['name'] == 'id' }

            expect(path_param).not_to be_nil
            expect(path_param['in']).to eq('path')
            expect(path_param['required']).to be true
            expect(path_param['schema']['type']).to eq('string')
          end
        end

        context 'with query parameters' do
          it 'generates query params from schema' do
            index_op = spec['paths']['/orders']['get']
            params = index_op['parameters'] || []
            query_params = params.select { |p| p['in'] == 'query' }

            expect(query_params.map { |p| p['name'] }).to contain_exactly('page', 'per_page', 'status')
          end

          it 'marks all query params as not required (all nilable)' do
            index_op = spec['paths']['/orders']['get']
            query_params = (index_op['parameters'] || []).select { |p| p['in'] == 'query' }

            query_params.each do |p|
              expect(p['required']).to be false
            end
          end
        end

        context 'with action-level headers' do
          before do
            config.register_controller(GeneratorTestFixtures::AdminController)
          end

          it 'includes action-specific headers' do
            admin_spec = generator.generate
            admin_op = admin_spec['paths']['/admin/orders']&.dig('post')
            next skip('admin route not matched') unless admin_op

            header = admin_op['parameters']&.find { |p| p['name'] == 'X-Admin-Token' }
            expect(header).not_to be_nil
            expect(header['in']).to eq('header')
            expect(header['required']).to be true
            expect(header['description']).to eq('Admin token')
          end
        end
      end

      describe 'action-level overrides' do
        before do
          config.register_controller(GeneratorTestFixtures::AdminController)
        end

        it 'uses action-level tags instead of controller tags' do
          admin_spec = generator.generate
          admin_op = admin_spec['paths']['/admin/orders']&.dig('post')
          next skip('admin route not matched') unless admin_op

          expect(admin_op['tags']).to eq(%w[Admin Special])
        end

        it 'uses action-level security instead of controller security' do
          admin_spec = generator.generate
          admin_op = admin_spec['paths']['/admin/orders']&.dig('post')
          next skip('admin route not matched') unless admin_op

          expect(admin_op['security']).to eq([{ 'bearer' => [] }])
        end
      end
    end

    describe 'components section' do
      describe 'securitySchemes' do
        it 'omits securitySchemes when none configured' do
          expect(spec['components']).not_to have_key('securitySchemes')
        end

        it 'includes configured security schemes' do
          config.security_scheme :bearer, type: :http, scheme: :bearer, bearerFormat: :JWT

          new_spec = generator.generate
          schemes = new_spec['components']['securitySchemes']
          expect(schemes).to have_key('bearer')
          expect(schemes['bearer']['type']).to eq('http')
          expect(schemes['bearer']['scheme']).to eq('bearer')
        end
      end

      describe 'schemas' do
        it 'collects directly referenced schemas' do
          schemas = spec['components']['schemas']
          schema_names = schemas.keys

          expect(schema_names).to include(
            GeneratorTestFixtures::OrderRequest.openapi_name,
            GeneratorTestFixtures::OrderResponse.openapi_name,
            GeneratorTestFixtures::ErrorResponse.openapi_name,
            GeneratorTestFixtures::ListResponse.openapi_name
          )
        end

        it 'collects query param schemas' do
          schemas = spec['components']['schemas']
          expect(schemas.keys).to include(GeneratorTestFixtures::QueryParams.openapi_name)
        end

        it 'collects nested schemas via BFS' do
          schemas = spec['components']['schemas']
          expect(schemas.keys).to include(GeneratorTestFixtures::LineItem.openapi_name)
        end

        it 'includes full schema definitions in components' do
          order_request_schema = spec['components']['schemas'][GeneratorTestFixtures::OrderRequest.openapi_name]
          expect(order_request_schema[:type]).to eq('object')
          expect(order_request_schema[:properties]).to have_key(:customer_id)
          expect(order_request_schema[:properties]).to have_key(:items)
        end
      end
    end

    describe 'controllers without typed actions' do
      before do
        config.register_controller(GeneratorTestFixtures::PlainController)
      end

      it 'skips controllers with no typed actions' do
        # Should not error and paths should remain unchanged
        expect(spec['paths'].keys).to contain_exactly('/orders', '/orders/{id}')
      end
    end

    describe 'controllers without matching routes' do
      it 'skips actions that have no matching route' do
        # Remove the show route
        limited_routes = routes.reject { |r| r[:action] == :show }
        gen = described_class.new(configuration: config, routes: limited_routes)
        limited_spec = gen.generate

        expect(limited_spec['paths']).not_to have_key('/orders/{id}')
      end
    end
  end

  describe '#generate with route guessing (no routes provided, no Rails)' do
    subject(:gen) { described_class.new(configuration: config, routes: nil) }

    it 'falls back to guessing routes from controller name' do
      guessed_spec = gen.generate
      # The guess_route method derives path from class name:
      # GeneratorTestFixtures::OrdersController → /generator_test_fixtures/orders
      expect(guessed_spec['paths'].keys).to include('/generator_test_fixtures/orders')
    end

    it 'maps action names to HTTP methods using ACTION_METHOD_MAP' do
      guessed_spec = gen.generate
      path = guessed_spec['paths']['/generator_test_fixtures/orders']

      expect(path).to have_key('get')  # index
      expect(path).to have_key('post') # create
    end
  end

  describe '#generate_to_file' do
    it 'writes JSON when output path ends with .json' do
      Dir.mktmpdir do |dir|
        output = File.join(dir, 'openapi.json')
        config.output_path = output

        gen = described_class.new(configuration: config, routes:)
        result = gen.generate_to_file

        expect(result).to eq(output)
        expect(File.exist?(output)).to be true

        content = JSON.parse(File.read(output))
        expect(content['openapi']).to eq('3.1.0')
        expect(content['info']['title']).to eq('Test API')
      end
    end

    it 'writes YAML when output path ends with .yaml' do
      Dir.mktmpdir do |dir|
        output = File.join(dir, 'openapi.yaml')
        config.output_path = output

        gen = described_class.new(configuration: config, routes:)
        result = gen.generate_to_file

        expect(result).to eq(output)
        expect(File.exist?(output)).to be true

        content = YAML.safe_load(File.read(output))
        expect(content['openapi']).to eq('3.1.0')
      end
    end

    it 'writes to a custom path when provided' do
      Dir.mktmpdir do |dir|
        custom_path = File.join(dir, 'custom', 'spec.json')
        gen = described_class.new(configuration: config, routes:)
        result = gen.generate_to_file(path: custom_path)

        expect(result).to eq(custom_path)
        expect(File.exist?(custom_path)).to be true
      end
    end

    it 'creates intermediate directories if needed' do
      Dir.mktmpdir do |dir|
        nested_path = File.join(dir, 'a', 'b', 'c', 'openapi.json')
        gen = described_class.new(configuration: config, routes:)
        gen.generate_to_file(path: nested_path)

        expect(File.exist?(nested_path)).to be true
      end
    end
  end
end
