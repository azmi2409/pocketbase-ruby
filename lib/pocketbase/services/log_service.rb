# frozen_string_literal: true

module PocketBase
  module Services
    # Logs service (port of js-sdk LogService).
    class LogService < BaseService
      # Returns a paginated logs list.
      def get_list(page = 1, per_page = 30, options = {})
        opts = send_options({ method: "GET" }, options)
        opts[:query] = { "page" => page, "perPage" => per_page }.merge(opts[:query] || {})
        @client.send_request("/api/logs", opts)
      end

      # Returns a single log by id (raises 404 when id is empty).
      def get_one(id, options = {})
        if id.nil? || id.to_s.empty?
          raise ClientResponseError.new(
            url: @client.build_url("/api/logs/"),
            status: 404,
            response: { "code" => 404, "message" => "Missing required log id.", "data" => {} }
          )
        end

        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/logs/#{Utils.encode_uri_component(id.to_s)}", opts)
      end

      # Returns logs statistics.
      def get_stats(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/logs/stats", opts)
      end

      # Deletes all logs. Returns true.
      def truncate(options = {})
        opts = send_options({ method: "DELETE" }, options)
        @client.send_request("/api/logs", opts)
        true
      end
    end
  end
end
