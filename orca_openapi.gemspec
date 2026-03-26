# frozen_string_literal: true

require_relative 'lib/orca_openapi/version'

Gem::Specification.new do |spec|
  spec.name = 'orca_openapi'
  spec.version = OrcaOpenAPI::VERSION
  spec.authors = ['Heber Uriegas']
  spec.email = ['heber@hireseals.ai']

  spec.summary = 'Generate OpenAPI 3.1 specs from Sorbet types — like FastAPI for Ruby.'
  spec.description = 'OrcaOpenAPI reads Sorbet type annotations on your Rails controllers, ' \
                     'params, and response structs to automatically generate OpenAPI 3.1 ' \
                     'specifications. No separate spec files, no DSL duplication — your ' \
                     'types are your documentation.'
  spec.homepage = 'https://github.com/seals-ai/orca_openapi'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/seals-ai/orca_openapi'
  spec.metadata['changelog_uri'] = 'https://github.com/seals-ai/orca_openapi/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  # Rails is optional — loaded conditionally for route introspection
  # spec.add_dependency "railties", ">= 7.0"
end
