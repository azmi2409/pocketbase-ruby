# frozen_string_literal: true

module PocketBase
  module Services
    # Batch service for transactional multi-requests (port of js-sdk BatchService).
    #
    #   batch = pb.create_batch
    #   batch.collection("posts").create(title: "hello")
    #   batch.collection("posts").update("RECORD_ID", title: "hi")
    #   batch.collection("posts").delete("OTHER_ID")
    #   results = batch.send  # => [{ "status" => 200, "body" => {...} }, ...]
    class BatchService < BaseService
      def initialize(client)
        super
        @requests = []
        @subs = {}
      end

      # Starts constructing a batch request entry for the given collection.
      def collection(collection_id_or_name)
        key = collection_id_or_name.to_s
        @subs[key] ||= SubBatchService.new(@requests, key, @client)
      end

      # Sends the queued batch requests.
      def send(options = {})
        form = MultipartBody.new
        json_data = []

        @requests.each_with_index do |req, i|
          json_data << {
            "method" => req[:method],
            "url" => req[:url],
            "headers" => req[:headers],
            "body" => req[:json],
          }
          (req[:files] || {}).each do |key, files|
            Array(files).each do |file|
              info = Multipart.file_info(file, key.to_s)
              form.add_file("requests.#{i}.#{key}", info[:filename], info[:content_type], info[:data])
            end
          end
        end

        form.add_json_payload({ "requests" => json_data })

        opts = send_options({ method: "POST", body: form }, options)
        @client.send_request("/api/batch", opts)
      end
    end

    # Per-collection batch request builder.
    class SubBatchService
      def initialize(requests, collection_id_or_name, client)
        @requests = requests
        @collection_id_or_name = collection_id_or_name
        @client = client
      end

      # Registers an upsert request (update when body has an existing id, else create).
      def upsert(body_params = nil, options = {})
        enqueue("PUT", base_records_path, body_params, options)
      end

      # Registers a create request.
      def create(body_params = nil, options = {})
        enqueue("POST", base_records_path, body_params, options)
      end

      # Registers an update request.
      def update(id, body_params = nil, options = {})
        enqueue("PATCH", "#{base_records_path}/#{Utils.encode_uri_component(id.to_s)}", body_params, options)
      end

      # Registers a delete request.
      def delete(id, options = {})
        enqueue("DELETE", "#{base_records_path}/#{Utils.encode_uri_component(id.to_s)}", nil, options)
      end

      private

      def base_records_path
        "/api/collections/#{Utils.encode_uri_component(@collection_id_or_name)}/records"
      end

      def enqueue(http_method, url, body_params, options)
        options = (options || {}).dup
        options[:body] = body_params || {}
        request = { method: http_method, url: url }
        prepare_request(request, options)
        @requests << request
        nil
      end

      def prepare_request(request, options)
        query = {}
        query.merge!(options.delete(:params)) if options[:params]
        query.merge!(options.delete(:query)) if options[:query]
        options.keys.each do |key|
          next if BaseService::SEND_OPTION_KEYS.include?(key.to_sym)

          query[key] = options.delete(key)
        end
        unless query.empty?
          serialized = Utils.serialize_query_params(query)
          request[:url] += (request[:url].include?("?") ? "&" : "?") + serialized unless serialized.empty?
        end

        request[:headers] = options[:headers]
        request[:json] = {}
        request[:files] = {}

        body = options[:body] || {}
        if body.is_a?(MultipartBody)
          raise ArgumentError, "pass a Hash (not a MultipartBody) as batch sub-request body"
        end

        body.each do |key, val|
          key = key.to_s
          if Multipart.file_value?(val)
            (request[:files][key] ||= []) << val
          elsif val.is_a?(Array)
            files = val.select { |v| Multipart.file_value?(v) }
            regular = val.reject { |v| Multipart.file_value?(v) }
            if files.any? && files.length == val.length
              (request[:files][key] ||= []).concat(files)
            else
              request[:json][key] = regular
              if files.any?
                file_key = key
                file_key += "+" unless key.start_with?("+") || key.end_with?("+")
                (request[:files][file_key] ||= []).concat(files)
              end
            end
          else
            request[:json][key] = val
          end
        end
      end

    end
  end
end
