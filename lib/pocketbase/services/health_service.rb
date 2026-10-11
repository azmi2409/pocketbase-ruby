# frozen_string_literal: true

module PocketBase
  module Services
    # Health service (port of js-sdk HealthService).
    class HealthService < BaseService
      # Checks the health status of the API.
      def check(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/health", opts)
      end
    end
  end
end
