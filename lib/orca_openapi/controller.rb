# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Mixin for Rails controllers to declare typed API actions.
  #
  # Provides the `typed_action` class method that stores metadata about
  # each action's request params, response schemas, tags, and security.
  # The Generator reads this metadata to produce OpenAPI path items.
  #
  # Usage:
  #   class PricesController < ApplicationController
  #     include OrcaOpenAPI::Controller
  #
  #     security :bearer
  #     tags "Products"
  #
  #     typed_action :create,
  #       summary: "Get product prices",
  #       params: PricesRequest,
  #       response: { 200 => PricesResponse, 422 => ErrorResponse }
  #   end
  #
  module Controller
    def self.included(base)
      base.extend(ClassMethods)

      # Auto-register the controller with the global configuration so it
      # appears in the generated spec without manual register_controller calls.
      OrcaOpenAPI.configuration.register_controller(base) if OrcaOpenAPI.configured?
    end

    # Stores metadata for a single typed action.
    ActionMeta = Struct.new(
      :action_name,
      :summary,
      :description,
      :tags,
      :security,
      :params_schema,
      :response_schemas,
      :path_params,
      :query_params,
      :headers,
      keyword_init: true
    )

    module ClassMethods
      # Declares a typed action on this controller.
      #
      # @param action_name [Symbol] The controller action (:index, :create, :show, etc.)
      # @param summary [String] Short summary for OpenAPI
      # @param description [String, nil] Longer description
      # @param tags [Array<String>, String, nil] OpenAPI tags (defaults to controller-level tags)
      # @param security [Array, Symbol, nil] Security override for this action
      # @param params [Class<T::Struct>, Array<Class<T::Struct>>, nil] Request body schema class,
      #   or an array of T::Struct classes to produce an inline oneOf envelope
      # @param response [Hash{Integer => Class<OrcaOpenAPI::Schema>}] Response schemas by status code
      # @param path_params [Hash, nil] Path parameter definitions
      # @param query_params [Class<OrcaOpenAPI::Schema>, nil] Query parameter schema
      # @param headers [Hash, nil] Additional header definitions
      def typed_action(action_name, summary:, params: nil, response: {}, description: nil,
                       tags: nil, security: nil, path_params: nil, query_params: nil, headers: nil)
        action_tags = Array(tags || controller_tags)
        action_security = security || controller_security

        typed_actions[action_name] = ActionMeta.new(
          action_name:,
          summary:,
          description:,
          tags: action_tags,
          security: action_security,
          params_schema: params,
          response_schemas: response,
          path_params:,
          query_params:,
          headers:
        )
      end

      # Sets controller-level tags (inherited by all actions unless overridden).
      def tags(*values)
        if values.empty?
          @_orca_tags || []
        else
          @_orca_tags = values.flatten.map(&:to_s)
        end
      end

      # Sets controller-level security (inherited by all actions unless overridden).
      def security(*values)
        if values.empty?
          @_orca_security
        else
          @_orca_security = values.first
        end
      end

      # Returns all typed action metadata for this controller.
      def typed_actions
        @_orca_typed_actions ||= {}
      end

      # Returns true if this controller has any typed actions.
      def typed?
        typed_actions.any?
      end

      private

      def controller_tags
        @_orca_tags || []
      end

      def controller_security
        @_orca_security
      end
    end
  end
end
