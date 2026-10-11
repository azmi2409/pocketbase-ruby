# frozen_string_literal: true

module PocketBase
  module Services
    # Cron service (port of js-sdk CronService).
    class CronService < BaseService
      # Returns the list of all registered cron jobs.
      def get_full_list(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/crons", opts)
      end

      # Runs the specified cron job. Returns true.
      def run(job_id, options = {})
        opts = send_options({ method: "POST" }, options)
        @client.send_request("/api/crons/#{Utils.encode_uri_component(job_id.to_s)}", opts)
        true
      end
    end
  end
end
