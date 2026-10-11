# frozen_string_literal: true

module PocketBase
  module Services
    # Base CRUD service (port of js-sdk CrudService).
    class CrudService < BaseService
      # Base path for the crud actions (without trailing slash).
      def base_crud_path
        raise NotImplementedError, "subclass must define #base_crud_path"
      end

      # Response data decoder (identity by default; override in subclasses).
      def decode(data)
        data
      end

      # Returns all list items batch-fetched at once
      # (1000 items per request by default; change with `batch:`).
      #
      #   service.get_full_list(batch: 200, filter: "...")
      #   service.get_full_list(200, filter: "...")   # legacy positional form
      def get_full_list(batch = nil, options = {})
        if batch.is_a?(Hash)
          options = batch.merge(options)
          batch = nil
        end
        batch_size = batch || options.delete(:batch) || 1000
        get_full_list_batched(batch_size, options)
      end

      # Returns a paginated items list.
      #
      #   result = service.get_list(1, 30, filter: "...", sort: "-created")
      #   result["items"] # => Array of decoded items
      def get_list(page = 1, per_page = 30, options = {})
        opts = send_options({ method: "GET" }, options)
        opts[:query] = { "page" => page, "perPage" => per_page }.merge(opts[:query] || {})
        response = @client.send_request(base_crud_path, opts)
        response["items"] = (response["items"] || []).map { |item| decode(item) }
        response
      end

      # Returns the first item matching the filter (raises 404 when none found).
      def get_first_list_item(filter, options = {})
        opts = options.merge(
          request_key: "one_by_filter_#{base_crud_path}_#{filter}",
          filter: filter,
          skipTotal: 1
        )
        result = get_list(1, 1, opts)
        items = result["items"] || []
        if items.empty?
          raise ClientResponseError.new(
            status: 404,
            response: { "code" => 404, "message" => "The requested resource wasn't found.", "data" => {} }
          )
        end

        items[0]
      end

      # Returns a single item by id (raises 404 when id is empty).
      def get_one(id, options = {})
        if id.nil? || id.to_s.empty?
          raise ClientResponseError.new(
            url: @client.build_url(base_crud_path + "/"),
            status: 404,
            response: { "code" => 404, "message" => "Missing required record id.", "data" => {} }
          )
        end

        opts = send_options({ method: "GET" }, options)
        decode(@client.send_request("#{base_crud_path}/#{Utils.encode_uri_component(id.to_s)}", opts))
      end

      # Creates a new item. Pass a File/IO value inside body for file uploads.
      def create(body_params = nil, options = {})
        opts = send_options({ method: "POST", body: body_params }, options)
        decode(@client.send_request(base_crud_path, opts))
      end

      # Updates an existing item by id.
      def update(id, body_params = nil, options = {})
        opts = send_options({ method: "PATCH", body: body_params }, options)
        decode(@client.send_request("#{base_crud_path}/#{Utils.encode_uri_component(id.to_s)}", opts))
      end

      # Deletes an item by id. Returns true on success.
      def delete(id, options = {})
        opts = send_options({ method: "DELETE" }, options)
        @client.send_request("#{base_crud_path}/#{Utils.encode_uri_component(id.to_s)}", opts)
        true
      end

      private

      def get_full_list_batched(batch_size, options)
        options = (options || {}).merge(skipTotal: 1)
        result = []
        page = 1
        loop do
          list = get_list(page, batch_size || 1000, options)
          items = list["items"] || []
          result.concat(items)
          break if items.length < list["perPage"].to_i

          page += 1
        end
        result
      end
    end
  end
end
