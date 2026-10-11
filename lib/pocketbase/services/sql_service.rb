# frozen_string_literal: true

module PocketBase
  module Services
    # SQL service (port of js-sdk SQLService). Superusers only.
    class SQLService < BaseService
      # Executes a raw SQL query.
      def run(query, options = {})
        opts = send_options({ method: "POST", body: { "query" => query } }, options)
        @client.send_request("/api/sql", opts)
      end
    end
  end
end
