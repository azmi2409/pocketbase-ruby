# frozen_string_literal: true

module PocketBase
  module Services
    # File service (port of js-sdk FileService).
    class FileService < BaseService
      # Builds an absolute record file URL for the given filename.
      #
      #   pb.files.get_url(record, "avatar.png", thumb: "100x100", download: true)
      def get_url(record, filename, query_params = {})
        record ||= {}
        collection = record["collectionId"] || record[:collectionId] ||
                     record["collectionName"] || record[:collectionName]
        id = record["id"] || record[:id]
        return "" if filename.nil? || filename.to_s.empty? || id.nil? || collection.nil?

        parts = ["api", "files",
                 Utils.encode_uri_component(collection.to_s),
                 Utils.encode_uri_component(id.to_s),
                 Utils.encode_uri_component(filename.to_s)]
        result = @client.build_url(parts.join("/"))

        query_params.delete(:download) if query_params[:download] == false
        query_params.delete("download") if query_params["download"] == false

        params = Utils.serialize_query_params(query_params)
        result += (result.include?("?") ? "&" : "?") + params unless params.empty?
        result
      end

      # Requests a new private file access token for the current auth model.
      def get_token(options = {})
        opts = send_options({ method: "POST" }, options)
        data = @client.send_request("/api/files/token", opts)
        data["token"] || data[:token] || ""
      end
    end
  end
end
