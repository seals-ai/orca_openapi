# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Assembles a complete OpenAPI 3.1 specification from:
  #   - Global configuration (title, version, servers, security schemes)
  #   - Registered controllers with typed_action declarations
  #   - Route information (path + HTTP method per action)
  #
  # Metadata (description, format, example) is read from T::Struct field_metadata,
  # which is automatically available via OrcaOpenAPI::StructExtension.
  #
  # Usage:
  #   spec = OrcaOpenAPI::Generator.new.generate
  #   # => Hash representing a complete OpenAPI 3.1 document
  #
  class Generator
    # HTTP method mapping from Rails action names to OpenAPI operations.
    ACTION_METHOD_MAP = {
      index: 'get',
      show: 'get',
      create: 'post',
      update: 'put',
      destroy: 'delete',
      new: 'get',
      edit: 'get'
    }.freeze

    def initialize(configuration: OrcaOpenAPI.configuration, routes: nil)
      @config = configuration
      @routes = routes # Optional: array of { controller:, action:, path:, method: } hashes
    end

    # Generates the complete OpenAPI 3.1 specification.
    #
    # @return [Hash] OpenAPI document
    def generate
      {
        'openapi' => '3.1.0',
        'info' => build_info,
        'servers' => build_servers,
        'paths' => build_paths,
        'components' => build_components
      }
    end

    # Generates and writes the spec to the configured output path.
    def generate_to_file(path: nil)
      output = path || @config.output_path
      spec = generate

      dir = File.dirname(output)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)

      content = if output.end_with?('.json') || @config.output_format == :json
                  require 'json'
                  JSON.pretty_generate(spec)
                else
                  require 'yaml'
                  YAML.dump(spec)
                end

      File.write(output, content)
      output
    end

    private

    def build_info
      info = {
        'title' => @config.title,
        'version' => @config.version
      }
      info['description'] = @config.description if @config.description
      info
    end

    def build_servers
      [{ 'url' => @config.server_url }]
    end

    def build_paths
      paths = {}

      @config.controllers.each do |controller_class|
        next unless controller_class.respond_to?(:typed_actions)

        controller_class.typed_actions.each do |action_name, action_meta|
          route = find_route(controller_class, action_name)
          next unless route

          path = route[:path]
          method = route[:method]

          paths[path] ||= {}
          paths[path][method] = build_operation(action_meta, route)
        end
      end

      paths
    end

    def build_operation(action_meta, route)
      operation = {}
      operation['summary'] = action_meta.summary if action_meta.summary
      operation['description'] = action_meta.description if action_meta.description
      operation['tags'] = action_meta.tags unless action_meta.tags.empty?
      operation['operationId'] = build_operation_id(route)

      # Security
      operation['security'] = [{ action_meta.security.to_s => [] }] if action_meta.security

      # Parameters (path params + query params + global headers)
      parameters = build_parameters(action_meta, route)
      operation['parameters'] = parameters unless parameters.empty?

      # Request body
      operation['requestBody'] = build_request_body(action_meta.params_schema) if action_meta.params_schema

      # Responses
      operation['responses'] = build_responses(action_meta.response_schemas)

      operation
    end

    def build_parameters(action_meta, route)
      params = []

      # Global headers
      @config.global_headers.each do |name, opts|
        params << {
          'name' => name,
          'in' => 'header',
          'required' => opts.fetch(:required, false),
          'schema' => { 'type' => opts.fetch(:type, 'string').to_s }.tap do |s|
            s['format'] = opts[:format].to_s if opts[:format]
          end
        }.tap { |p| p['description'] = opts[:description] if opts[:description] }
      end

      # Path parameters from route
      if route[:path_params]
        route[:path_params].each do |param_name|
          params << {
            'name' => param_name.to_s,
            'in' => 'path',
            'required' => true,
            'schema' => { 'type' => 'string' }
          }
        end
      end

      # Query parameters
      if action_meta.query_params
        schema = struct_to_openapi_schema(action_meta.query_params)
        (schema[:properties] || {}).each do |prop_name, prop_schema|
          required = (schema[:required] || []).include?(prop_name.to_s)
          params << {
            'name' => prop_name.to_s,
            'in' => 'query',
            'required' => required,
            'schema' => prop_schema
          }
        end
      end

      # Action-specific headers
      if action_meta.headers
        action_meta.headers.each do |name, opts|
          params << {
            'name' => name.to_s,
            'in' => 'header',
            'required' => opts.fetch(:required, false),
            'schema' => { 'type' => opts.fetch(:type, 'string').to_s }
          }.tap { |p| p['description'] = opts[:description] if opts[:description] }
        end
      end

      params
    end

    def build_request_body(schema_class)
      {
        'required' => true,
        'content' => {
          'application/json' => {
            'schema' => { '$ref' => "#/components/schemas/#{openapi_name_for(schema_class)}" }
          }
        }
      }
    end

    def build_responses(response_schemas)
      responses = {}

      response_schemas.each do |status, schema_class|
        status_str = status.to_s
        response = { 'description' => default_status_description(status) }

        if schema_class
          response['content'] = {
            'application/json' => {
              'schema' => { '$ref' => "#/components/schemas/#{openapi_name_for(schema_class)}" }
            }
          }
        end

        responses[status_str] = response
      end

      # Ensure at least a default response
      responses['default'] = { 'description' => 'Unexpected error' } if responses.empty?

      responses
    end

    def build_components
      components = {}

      # Security schemes
      unless @config.security_schemes.empty?
        components['securitySchemes'] = @config.security_schemes.transform_keys(&:to_s)
      end

      # Collect all referenced schemas
      schemas = collect_schemas
      components['schemas'] = schemas unless schemas.empty?

      components
    end

    # BFS collects all T::Struct schema classes referenced by typed actions.
    def collect_schemas
      seen = {}
      queue = []

      # Seed from all controller actions
      @config.controllers.each do |controller_class|
        next unless controller_class.respond_to?(:typed_actions)

        controller_class.typed_actions.each_value do |action_meta|
          queue << action_meta.params_schema if action_meta.params_schema
          queue << action_meta.query_params if action_meta.query_params

          action_meta.response_schemas.each_value do |schema_class|
            queue << schema_class if schema_class
          end
        end
      end

      # BFS to find all nested schemas
      while (klass = queue.shift)
        next unless klass < T::Struct

        name = openapi_name_for(klass)
        next if seen.key?(name)

        schema = struct_to_openapi_schema(klass)
        seen[name] = schema

        # If the schema exposes variant schemas (e.g. oneOf wrappers), enqueue them
        klass.variant_schemas.each { |v| queue << v } if klass.respond_to?(:variant_schemas)

        # Find nested T::Struct references in properties
        enqueue_nested_structs(klass, queue)
      end

      seen
    end

    # Generates an OpenAPI 3.1 schema hash for a T::Struct class.
    # If the class defines a custom `to_openapi_schema`, delegates to it.
    # Otherwise, introspects T::Struct props directly and reads metadata
    # from field_metadata (available on all T::Struct via StructExtension).
    def struct_to_openapi_schema(klass)
      # Delegate to custom to_openapi_schema if the class defines one
      # (e.g. oneOf wrappers that include OrcaOpenAPI::Schema)
      return klass.to_openapi_schema if klass.respond_to?(:to_openapi_schema)

      props = {}
      required = []
      metadata = klass.respond_to?(:field_metadata) ? klass.field_metadata : {}

      klass.props.each do |prop_name, prop_info|
        type_object = prop_info[:type_object] || prop_info[:type]
        schema = TypeConverter.convert(type_object)

        # Read metadata from field_metadata (populated by StructExtension's const override)
        meta = metadata[prop_name] || {}
        schema[:description] = meta[:description] if meta[:description]
        schema[:format] = meta[:format] if meta[:format]
        schema[:example] = meta[:example] unless meta[:example].nil?

        props[prop_name] = schema

        # A field is required if it's not nilable and has no default
        required << prop_name.to_s unless nilable_type?(type_object) || prop_info.key?(:default)
      end

      result = { type: 'object', properties: props }
      result[:required] = required unless required.empty?
      result
    end

    # Finds nested T::Struct references in a class's props and enqueues them.
    def enqueue_nested_structs(klass, queue)
      return unless klass.respond_to?(:props)

      klass.props.each_value do |prop_info|
        type_obj = prop_info[:type_object] || prop_info[:type]
        find_struct_classes(type_obj, queue)
      end
    end

    def find_struct_classes(type_obj, queue)
      case type_obj
      when T::Types::TypedArray
        find_struct_classes(type_obj.type, queue)
      when T::Types::Simple
        klass = type_obj.raw_type
        queue << klass if klass < T::Struct
      when T::Types::Union
        type_obj.types.each { |t| find_struct_classes(t, queue) }
      end
    rescue StandardError
      # Skip types that can't be introspected
    end

    # Derives the OpenAPI component name for a T::Struct class.
    # Delegates to `openapi_name` if available (via StructExtension),
    # otherwise derives from the class name.
    def openapi_name_for(klass)
      if klass.respond_to?(:openapi_name)
        klass.openapi_name
      else
        klass.name.gsub('::', '_').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end

    # Finds the route for a given controller + action.
    # Uses the manually provided routes or falls back to Rails router introspection.
    def find_route(controller_class, action_name)
      if @routes
        # Manual route lookup
        controller_path = pure_underscore(controller_class.name).delete_suffix('_controller')
        @routes.find do |r|
          r[:controller] == controller_path && r[:action].to_sym == action_name
        end
      elsif defined?(Rails) && Rails.application
        find_rails_route(controller_class, action_name)
      else
        # Fallback: guess from controller name and action
        guess_route(controller_class, action_name)
      end
    end

    def find_rails_route(controller_class, action_name)
      controller_path = pure_underscore(controller_class.name).delete_suffix('_controller')

      Rails.application.routes.routes.each do |route|
        defaults = route.defaults
        next unless defaults[:controller] == controller_path
        next unless defaults[:action] == action_name.to_s

        path = route.path.spec.to_s.gsub('(.:format)', '').gsub(/:(\w+)/, '{\1}')
        method = route.verb.downcase

        path_params = route.path.spec.to_s.scan(/:(\w+)/).flatten.reject { |p| p == 'format' }

        return {
          path:,
          method:,
          controller: controller_path,
          action: action_name,
          path_params:
        }
      end

      nil
    end

    def guess_route(controller_class, action_name)
      # Derive path from controller namespace
      parts = controller_class.name.delete_suffix('Controller').split('::')
      path = '/' + parts.map { |p| p.gsub(/([a-z])([A-Z])/, '\1_\2').downcase }.join('/')

      method = ACTION_METHOD_MAP.fetch(action_name, 'post')

      {
        path:,
        method:,
        controller: pure_underscore(controller_class.name).delete_suffix('_controller'),
        action: action_name,
        path_params: []
      }
    end

    def build_operation_id(route)
      "#{route[:controller].tr('/', '_')}_#{route[:action]}"
    end

    def default_status_description(status)
      descriptions = {
        200 => 'Successful response',
        201 => 'Created',
        204 => 'No content',
        400 => 'Bad request',
        401 => 'Unauthorized',
        403 => 'Forbidden',
        404 => 'Not found',
        422 => 'Unprocessable entity',
        500 => 'Internal server error'
      }
      descriptions.fetch(status, "Response #{status}")
    end

    def nilable_type?(type)
      return false unless type.is_a?(T::Types::Union)

      type.types.any? { |t| t.is_a?(T::Types::Simple) && t.raw_type == NilClass }
    end

    # Pure-Ruby equivalent of ActiveSupport's String#underscore.
    # Converts CamelCase / namespaced class names to snake_case paths.
    #   "GeneratorTestFixtures::OrdersController" => "generator_test_fixtures/orders_controller"
    def pure_underscore(str)
      str.gsub('::', '/')
         .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .downcase
    end
  end
end
