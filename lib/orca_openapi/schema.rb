# frozen_string_literal: true
# typed: strict

module OrcaOpenAPI
  # DEPRECATED: This module is no longer needed.
  #
  # As of orca_openapi 0.2.0, all T::Struct subclasses automatically support
  # `description:`, `format:`, and `example:` kwargs on `const`/`prop` via
  # OrcaOpenAPI::StructExtension (loaded at gem require time).
  #
  # `include OrcaOpenAPI::Schema` is now a silent no-op for backward compatibility.
  # You can safely remove it from your T::Struct subclasses.
  module Schema
    def self.included(base)
      # No-op. The struct_extension prepend handles everything globally.
    end
  end
end
