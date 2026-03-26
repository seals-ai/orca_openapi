# frozen_string_literal: true

require 'spec_helper'

# -- Fixture schemas for controller tests --

module ControllerTestFixtures
  class CreateRequest < T::Struct
    const :name, String, description: 'Item name'
    const :quantity, Integer
  end

  class CreateResponse < T::Struct
    const :id, String, description: 'Created item ID'
    const :name, String
  end

  class ErrorResponse < T::Struct
    const :error, String, description: 'Error message'
  end

  class IndexResponse < T::Struct
    const :items, T::Array[CreateResponse]
    const :total, Integer
  end

  class QueryParams < T::Struct
    const :page, T.nilable(Integer), description: 'Page number'
    const :per_page, T.nilable(Integer), description: 'Items per page'
  end
end

RSpec.describe OrcaOpenAPI::Controller do
  # Build fresh controller classes per-context to avoid state leaking between tests.
  # Using Class.new + const_set so the controller has a proper name for route guessing.

  describe 'module inclusion' do
    it 'extends ClassMethods on the including class' do
      controller = Class.new { include OrcaOpenAPI::Controller }

      expect(controller).to respond_to(:typed_action)
      expect(controller).to respond_to(:tags)
      expect(controller).to respond_to(:security)
      expect(controller).to respond_to(:typed_actions)
      expect(controller).to respond_to(:typed?)
    end
  end

  describe '.tags' do
    it 'returns empty array when no tags are set' do
      controller = Class.new { include OrcaOpenAPI::Controller }
      expect(controller.tags).to eq([])
    end

    it 'sets and returns tags as strings' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        tags 'Products', 'Inventory'
      end

      expect(controller.tags).to eq(%w[Products Inventory])
    end

    it 'coerces symbol tags to strings' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        tags :products, :inventory
      end

      expect(controller.tags).to eq(%w[products inventory])
    end

    it 'flattens nested arrays' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        tags %w[A B], 'C'
      end

      expect(controller.tags).to eq(%w[A B C])
    end
  end

  describe '.security' do
    it 'returns nil when no security is set' do
      controller = Class.new { include OrcaOpenAPI::Controller }
      expect(controller.security).to be_nil
    end

    it 'sets and returns security value' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        security :bearer
      end

      expect(controller.security).to eq(:bearer)
    end
  end

  describe '.typed_action' do
    it 'stores an ActionMeta for the given action' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create an item',
                     params: ControllerTestFixtures::CreateRequest,
                     response: {
                       200 => ControllerTestFixtures::CreateResponse,
                       422 => ControllerTestFixtures::ErrorResponse
                     }
      end

      expect(controller.typed_actions).to have_key(:create)
      meta = controller.typed_actions[:create]
      expect(meta).to be_a(OrcaOpenAPI::Controller::ActionMeta)
    end

    it 'stores summary' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create an item',
                     params: ControllerTestFixtures::CreateRequest,
                     response: { 200 => ControllerTestFixtures::CreateResponse }
      end

      expect(controller.typed_actions[:create].summary).to eq('Create an item')
    end

    it 'stores description' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create',
                     description: 'Creates a new item in the system',
                     response: {}
      end

      expect(controller.typed_actions[:create].description).to eq('Creates a new item in the system')
    end

    it 'stores params_schema' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create',
                     params: ControllerTestFixtures::CreateRequest,
                     response: {}
      end

      expect(controller.typed_actions[:create].params_schema).to eq(ControllerTestFixtures::CreateRequest)
    end

    it 'stores response_schemas by status code' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create',
                     response: {
                       200 => ControllerTestFixtures::CreateResponse,
                       422 => ControllerTestFixtures::ErrorResponse
                     }
      end

      responses = controller.typed_actions[:create].response_schemas
      expect(responses).to eq(
        200 => ControllerTestFixtures::CreateResponse,
        422 => ControllerTestFixtures::ErrorResponse
      )
    end

    it 'stores query_params' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :index,
                     summary: 'List items',
                     query_params: ControllerTestFixtures::QueryParams,
                     response: { 200 => ControllerTestFixtures::IndexResponse }
      end

      expect(controller.typed_actions[:index].query_params).to eq(ControllerTestFixtures::QueryParams)
    end

    it 'stores headers' do
      custom_headers = { 'X-Request-Id' => { type: :string, required: true } }

      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :create,
                     summary: 'Create',
                     headers: { 'X-Request-Id' => { type: :string, required: true } },
                     response: {}
      end

      expect(controller.typed_actions[:create].headers).to eq(custom_headers)
    end

    it 'stores path_params' do
      path_params = { id: { type: :string, format: :uuid } }

      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :show,
                     summary: 'Show item',
                     path_params: { id: { type: :string, format: :uuid } },
                     response: { 200 => ControllerTestFixtures::CreateResponse }
      end

      expect(controller.typed_actions[:show].path_params).to eq(path_params)
    end

    it 'defaults params_schema to nil when not provided' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        typed_action :index, summary: 'List', response: {}
      end

      expect(controller.typed_actions[:index].params_schema).to be_nil
    end

    it 'defaults description to nil when not provided' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        typed_action :index, summary: 'List', response: {}
      end

      expect(controller.typed_actions[:index].description).to be_nil
    end
  end

  describe 'tag inheritance' do
    it 'inherits controller-level tags when action does not override' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        tags 'Products'

        typed_action :create,
                     summary: 'Create',
                     response: {}
      end

      expect(controller.typed_actions[:create].tags).to eq(['Products'])
    end

    it 'uses action-level tags when provided, overriding controller tags' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        tags 'Products'

        typed_action :create,
                     summary: 'Create',
                     tags: ['Custom'],
                     response: {}
      end

      expect(controller.typed_actions[:create].tags).to eq(['Custom'])
    end

    it 'defaults to empty tags when neither controller nor action sets them' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :index,
                     summary: 'List',
                     response: {}
      end

      expect(controller.typed_actions[:index].tags).to eq([])
    end
  end

  describe 'security inheritance' do
    it 'inherits controller-level security when action does not override' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        security :bearer

        typed_action :create,
                     summary: 'Create',
                     response: {}
      end

      expect(controller.typed_actions[:create].security).to eq(:bearer)
    end

    it 'uses action-level security when provided, overriding controller security' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        security :bearer

        typed_action :create,
                     summary: 'Create',
                     security: :api_key,
                     response: {}
      end

      expect(controller.typed_actions[:create].security).to eq(:api_key)
    end

    it 'defaults to nil when neither controller nor action sets security' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :index,
                     summary: 'List',
                     response: {}
      end

      expect(controller.typed_actions[:index].security).to be_nil
    end
  end

  describe '.typed_actions' do
    it 'returns empty hash when no actions registered' do
      controller = Class.new { include OrcaOpenAPI::Controller }
      expect(controller.typed_actions).to eq({})
    end

    it 'returns all registered actions' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :index,
                     summary: 'List items',
                     response: { 200 => ControllerTestFixtures::IndexResponse }

        typed_action :create,
                     summary: 'Create item',
                     params: ControllerTestFixtures::CreateRequest,
                     response: { 200 => ControllerTestFixtures::CreateResponse }
      end

      expect(controller.typed_actions.keys).to contain_exactly(:index, :create)
    end

    it 'stores each action independently' do
      controller = Class.new do
        include OrcaOpenAPI::Controller

        typed_action :index,
                     summary: 'List',
                     response: { 200 => ControllerTestFixtures::IndexResponse }

        typed_action :create,
                     summary: 'Create',
                     params: ControllerTestFixtures::CreateRequest,
                     response: { 200 => ControllerTestFixtures::CreateResponse }
      end

      expect(controller.typed_actions[:index].summary).to eq('List')
      expect(controller.typed_actions[:create].summary).to eq('Create')
      expect(controller.typed_actions[:index].params_schema).to be_nil
      expect(controller.typed_actions[:create].params_schema).to eq(ControllerTestFixtures::CreateRequest)
    end
  end

  describe '.typed?' do
    it 'returns false when no actions are registered' do
      controller = Class.new { include OrcaOpenAPI::Controller }
      expect(controller.typed?).to be false
    end

    it 'returns true when actions are registered' do
      controller = Class.new do
        include OrcaOpenAPI::Controller
        typed_action :index, summary: 'List', response: {}
      end

      expect(controller.typed?).to be true
    end
  end

  describe 'isolation between controllers' do
    it 'does not share typed_actions between different controller classes' do
      controller_a = Class.new do
        include OrcaOpenAPI::Controller
        typed_action :index, summary: 'A index', response: {}
      end

      controller_b = Class.new do
        include OrcaOpenAPI::Controller
        typed_action :create, summary: 'B create', response: {}
      end

      expect(controller_a.typed_actions.keys).to eq([:index])
      expect(controller_b.typed_actions.keys).to eq([:create])
    end

    it 'does not share tags between different controller classes' do
      controller_a = Class.new do
        include OrcaOpenAPI::Controller
        tags 'Alpha'
      end

      controller_b = Class.new do
        include OrcaOpenAPI::Controller
        tags 'Beta'
      end

      expect(controller_a.tags).to eq(['Alpha'])
      expect(controller_b.tags).to eq(['Beta'])
    end

    it 'does not share security between different controller classes' do
      controller_a = Class.new do
        include OrcaOpenAPI::Controller
        security :bearer
      end

      controller_b = Class.new do
        include OrcaOpenAPI::Controller
        security :api_key
      end

      expect(controller_a.security).to eq(:bearer)
      expect(controller_b.security).to eq(:api_key)
    end
  end
end
