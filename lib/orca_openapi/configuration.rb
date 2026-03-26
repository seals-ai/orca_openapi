# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # Global configuration for OrcaOpenAPI.
  #
  # Usage:
  #   OrcaOpenAPI.configure do |c|
  #     c.title = "My API"
  #     c.version = "1.0.0"
  #     c.server_url = "https://api.example.com"
  #     c.output_path = "swagger/v1/openapi.yaml"
  #     c.security_scheme :bearer, type: :http, scheme: :bearer
  #     c.global_header "X-Company-ID", type: :string, format: :uuid
  #   end
  #
  class Configuration
    attr_accessor :title, :version, :description, :server_url, :output_path, :output_format

    def initialize
      @title = 'API'
      @version = '1.0.0'
      @description = nil
      @server_url = 'http://localhost:3000'
      @output_path = 'swagger/v1/openapi.json'
      @output_format = :json
      @security_schemes = {}
      @global_headers = {}
      @controllers = []
    end

    # Registers a named security scheme.
    #
    # @param name [Symbol] Scheme name (e.g., :bearer)
    # @param options [Hash] OpenAPI security scheme object fields
    def security_scheme(name, **options)
      @security_schemes[name] = stringify_keys(options)
    end

    # Registers a global header parameter.
    #
    # @param name [String] Header name (e.g., "X-Company-ID")
    # @param options [Hash] Schema options (type, format, required, description)
    def global_header(name, **options)
      @global_headers[name] = options
    end

    # Registers a controller class to include in spec generation.
    # Called automatically when a controller includes OrcaOpenAPI::Controller.
    def register_controller(controller_class)
      @controllers << controller_class unless @controllers.include?(controller_class)
    end

    # Returns all registered security schemes.
    def security_schemes
      @security_schemes.dup
    end

    # Returns all registered global headers.
    def global_headers
      @global_headers.dup
    end

    # Returns all registered controller classes.
    def controllers
      @controllers.dup
    end

    private

    def stringify_keys(hash)
      hash.transform_keys(&:to_s).transform_values do |v|
        v.is_a?(Hash) ? stringify_keys(v) : v.to_s
      end
    end
  end
end
