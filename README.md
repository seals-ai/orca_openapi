# OrcaOpenAPI

Generate OpenAPI 3.1 specs from Sorbet types — like FastAPI for Ruby.

OrcaOpenAPI reads Sorbet type annotations on your Rails controllers, params, and response structs to automatically generate OpenAPI specifications. No separate spec files, no DSL duplication — your types are your documentation.

## Installation

Add to your Gemfile:

```ruby
gem "orca_openapi"
```

Then run:

```bash
bundle install
```

## Quick Start

### 1. Define typed schemas

```ruby
class PricesRequest < OrcaOpenAPI::Schema
  const :product_ids, T::Array[String], description: "List of product UUIDs"
  const :customer_id, T.nilable(String), description: "Customer UUID for customer-specific pricing"
end

class PriceEntry < OrcaOpenAPI::Schema
  const :id, String, description: "Product UUID"
  const :price, T.nilable(Float), description: "Base catalog price"
  const :price_cents, T.nilable(Integer), description: "Base price in cents"
  const :customer_price, T.nilable(Float), description: "Customer-specific price"
end

class PricesResponse < OrcaOpenAPI::Schema
  const :products, T::Array[PriceEntry], description: "Product prices"
end
```

### 2. Declare typed actions on controllers

```ruby
class Llm::V1::Products::PricesController < ApplicationController
  include OrcaOpenAPI::Controller

  security :bearer
  tags "Product Prices"

  typed_action :create,
    summary: "Get product prices",
    params: PricesRequest,
    response: { 200 => PricesResponse, 422 => ErrorResponse }

  def create
    # Your existing controller logic — unchanged
  end
end
```

### 3. Generate the OpenAPI spec

```bash
bundle exec orca_openapi generate
```

This outputs `swagger/v1/openapi.yaml` (OpenAPI 3.1) by reading your Rails routes + typed controller declarations.

## Configuration

```ruby
# config/initializers/orca_openapi.rb
OrcaOpenAPI.configure do |c|
  c.title = "My API"
  c.version = "1.0.0"
  c.server_url = "https://api.example.com"
  c.output_path = Rails.root.join("swagger/v1/openapi.yaml")

  c.security_scheme :bearer, type: :http, scheme: :bearer
  c.global_header "X-Company-ID", type: :string, format: :uuid, required: false
end
```

## Development

```bash
bin/setup
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/seals-ai/orca_openapi.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
