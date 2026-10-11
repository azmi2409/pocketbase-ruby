# frozen_string_literal: true

module PocketBase
  module Services
    # Backup service (port of js-sdk BackupService).
    class BackupService < BaseService
      # Returns the list of all available backup files.
      def get_full_list(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("/api/backups", opts)
      end

      # Initializes a new backup. Returns true.
      def create(basename, options = {})
        opts = send_options({ method: "POST", body: { "name" => basename } }, options)
        @client.send_request("/api/backups", opts)
        true
      end

      # Uploads an existing backup file.
      #
      #   pb.backups.upload(file: File.open("backup.zip"))
      #   pb.backups.upload("file" => { filename: "b.zip", data: "..." })
      def upload(body_params = nil, options = {})
        opts = send_options({ method: "POST", body: body_params }, options)
        @client.send_request("/api/backups/upload", opts)
        true
      end

      # Deletes a single backup file. Returns true.
      def delete(key, options = {})
        opts = send_options({ method: "DELETE" }, options)
        @client.send_request("/api/backups/#{Utils.encode_uri_component(key.to_s)}", opts)
        true
      end

      # Initializes an app data restore from an existing backup. Returns true.
      def restore(key, options = {})
        opts = send_options({ method: "POST" }, options)
        @client.send_request("/api/backups/#{Utils.encode_uri_component(key.to_s)}/restore", opts)
        true
      end

      # Builds a download URL for a backup using a file token
      # (generate one via pb.files.get_token).
      def get_download_url(token, key)
        @client.build_url(
          "/api/backups/#{Utils.encode_uri_component(key.to_s)}" \
          "?token=#{Utils.encode_uri_component(token.to_s)}"
        )
      end
    end
  end
end
