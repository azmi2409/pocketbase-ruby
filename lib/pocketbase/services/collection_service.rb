# frozen_string_literal: true

module PocketBase
  module Services
    # Collection management service (port of js-sdk CollectionService).
    class CollectionService < CrudService
      def base_crud_path
        "/api/collections"
      end

      # Imports the provided collections.
      # If delete_missing is true, local collections not present in the
      # imported configuration WILL BE DELETED (including their records)!
      def import(collections, delete_missing = false, options = {})
        opts = send_options(
          { method: "PUT",
            body: { "collections" => collections, "deleteMissing" => delete_missing } },
          options
        )
        @client.send_request("#{base_crud_path}/import", opts)
        true
      end

      # Deletes all records of the given collection. Returns true.
      def truncate(collection_id_or_name, options = {})
        opts = send_options({ method: "DELETE" }, options)
        @client.send_request(
          "#{base_crud_path}/#{Utils.encode_uri_component(collection_id_or_name.to_s)}/truncate", opts
        )
        true
      end

      # Returns a type-indexed map of scaffolded collection models.
      def get_scaffolds(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("#{base_crud_path}/meta/scaffolds", opts)
      end

      # Returns the list of all configurable OAuth2 providers.
      def get_all_oauth2_providers(options = {})
        opts = send_options({ method: "GET" }, options)
        @client.send_request("#{base_crud_path}/meta/oauth2-providers", opts)
      end

      # Executes a view query and returns a sample of the resulting records.
      def dry_run_view_query(query, options = {})
        opts = send_options({ method: "POST", body: { "query" => query } }, options)
        @client.send_request("#{base_crud_path}/meta/dry-run-view", opts)
      end
    end
  end
end
