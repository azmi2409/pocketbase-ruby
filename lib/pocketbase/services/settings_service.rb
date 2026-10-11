# frozen_string_literal: true

module PocketBase
  module Services
    # Settings service (port of js-sdk SettingsService).
    class SettingsService < BaseService
      # Fetches all available app settings.
      def get_all(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/settings", opts)
      end

      # Bulk updates app settings.
      def update(body_params = nil, options = {})
        opts = send_options({ method: "PATCH", body: body_params }, options)
        @client.send_request("/api/settings", opts)
      end

      # Performs an S3 filesystem connection test ("storage" or "backups").
      def test_s3(filesystem = "storage", options = {})
        opts = send_options({ method: "POST", body: { "filesystem" => filesystem } }, options)
        @client.send_request("/api/settings/test/s3", opts)
        true
      end

      # Sends a test email (templates: verification, password-reset, email-change).
      def test_email(collection_id_or_name, to_email, email_template, options = {})
        opts = send_options(
          { method: "POST",
            body: { "email" => to_email, "template" => email_template,
                    "collection" => collection_id_or_name } },
          options
        )
        @client.send_request("/api/settings/test/email", opts)
        true
      end

      # Generates a new Apple OAuth2 client secret.
      def generate_apple_client_secret(client_id, team_id, key_id, private_key, duration, options = {})
        opts = send_options(
          { method: "POST",
            body: { "clientId" => client_id, "teamId" => team_id, "keyId" => key_id,
                    "privateKey" => private_key, "duration" => duration } },
          options
        )
        @client.send_request("/api/settings/apple/generate-client-secret", opts)
      end
    end
  end
end
