# frozen_string_literal: true
# typed: false

module OrcaOpenAPI
  # Extends Sorbet's `T::Props::Decorator` at gem load time so that ANY
  # T::Struct subclass automatically accepts `description:`, `format:`, and
  # `example:` keyword arguments on `const`/`prop` — no `include` needed.
  #
  # Metadata is stored directly in Sorbet's prop rules hash and can be read via
  # `MyStruct.props[:field_name][:description]`, etc.
  #
  # A convenience `field_metadata` class method is added to all T::Struct
  # subclasses to collect OpenAPI metadata in the same format the old
  # OrcaOpenAPI::Schema module used.
  #
  # Also adds `openapi_name` to every T::Struct subclass for consistent
  # OpenAPI component naming.
  #
  # Implementation: We prepend on `T::Props::Decorator` and override
  # `valid_rule_key?` (which is `sig checked(:never)` so Sorbet's runtime
  # will never replace it with an optimized validator). This is the cleanest
  # integration point — metadata keys pass validation, get stored in the
  # standard prop rules hash, and are accessible via `klass.props`.
  #
  # This is activated automatically when orca_openapi is required.
  module StructExtension
    # Metadata keys that OrcaOpenAPI registers as valid prop rule keys.
    METADATA_KEYS = %i[description format example].freeze

    # Prepended onto T::Props::Decorator to whitelist our metadata keys.
    module DecoratorExtension
      def valid_rule_key?(key)
        return true if METADATA_KEYS.include?(key)

        super
      end
    end

    def self.apply!
      # Allow description/format/example as valid prop rule keys.
      T::Props::Decorator.prepend(DecoratorExtension)

      # Add convenience methods to all T::Struct subclasses.
      T::Struct.singleton_class.prepend(InheritedHook)
    end

    # Hooks into T::Struct.inherited to add openapi_name and field_metadata
    # to every subclass.
    module InheritedHook
      def inherited(subclass)
        super
        subclass.extend(StructClassMethods)
      end
    end

    # Methods added to each T::Struct subclass.
    module StructClassMethods
      # Returns the OpenAPI component name for this T::Struct subclass.
      #   Llm::V1::Products::PricesResponse => "llm_v1_products_prices_response"
      def openapi_name
        name&.gsub('::', '_')&.gsub(/([a-z])([A-Z])/, '\1_\2')&.downcase || 'anonymous'
      end

      # Returns OpenAPI metadata for all fields that have any.
      # @return [Hash{Symbol => Hash}]  e.g. { name: { description: "User's full name" } }
      def field_metadata
        result = {}
        props.each do |prop_name, rules|
          meta = {}
          METADATA_KEYS.each { |k| meta[k] = rules[k] if rules.key?(k) }
          result[prop_name] = meta unless meta.empty?
        end
        result
      end
    end
  end
end

# Activate the extension at load time.
OrcaOpenAPI::StructExtension.apply!
