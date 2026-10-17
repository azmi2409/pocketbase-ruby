# frozen_string_literal: true

require_relative "lib/pocketbase/version"

Gem::Specification.new do |s|
  s.name = "pocketbase"
  s.version = PocketBase::VERSION
  s.authors = ["Azmi Muwahid"]
  s.email = ["azmimuwahid@gmail.com"]
  s.summary = "Ruby SDK for PocketBase"
  s.description = "A Ruby port of the official PocketBase JavaScript SDK " \
                  "(pocketbase/js-sdk): record CRUD, auth (password, OAuth2, OTP), " \
                  "file uploads, realtime subscriptions over SSE, backups, " \
                  "settings, logs, cron jobs, SQL and batch requests. " \
                  "Zero runtime dependencies (stdlib only)."
  s.homepage = "https://github.com/azmi2409/pocketbase-ruby"
  s.license = "MIT"
  s.required_ruby_version = ">= 2.7"

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => "#{s.homepage}/tree/main",
    "bug_tracker_uri" => "#{s.homepage}/issues",
    "changelog_uri" => "#{s.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/pocketbase/#{s.version}",
    "allowed_push_host" => "https://rubygems.org"
  }

  s.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  s.require_paths = ["lib"]

  # base64 is a bundled gem, not a default gem, since Ruby 3.4 — declare it so
  # `require "base64"` keeps working there. Still stdlib-only, no third-party deps.
  s.add_dependency "base64"
end
