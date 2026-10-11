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

  s.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  s.require_paths = ["lib"]
end
