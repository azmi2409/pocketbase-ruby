# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module PocketBase
  # PocketBase API client (port of the js-sdk Client).
  #
  #   pb = PocketBase::Client.new("http://127.0.0.1:8090")
  #   pb.collection("users").auth_with_password("test@example.com", "1234567890")
  class Client
    # Options that are treated as send options; anything else passed at the
    # top level of an options hash is moved into the query string
    # (mirrors js-sdk normalizeUnknownQueryParams).
    KNOWN_SEND_OPTIONS = %i[
      method headers body query params request_key timeout
      fetch signal
    ].freeze

    attr_accessor :base_url, :lang, :auth_store, :before_send, :after_send
    attr_reader :settings, :collections, :files, :logs, :realtime,
                :health, :backups, :crons, :sql

    def initialize(base_url = "/", auth_store: nil, lang: "en-US")
      @base_url = base_url.to_s
      @lang = lang
      @auth_store = auth_store || AuthStore.new
      @before_send = nil
      @after_send = nil
      @record_services = {}
      @enable_auto_cancellation = true

      @settings = Services::SettingsService.new(self)
      @collections = Services::CollectionService.new(self)
      @files = Services::FileService.new(self)
      @logs = Services::LogService.new(self)
      @realtime = Services::RealtimeService.new(self)
      @health = Services::HealthService.new(self)
      @backups = Services::BackupService.new(self)
      @crons = Services::CronService.new(self)
      @sql = Services::SQLService.new(self)
    end

    # Returns the RecordService for a collection (cached per idOrName).
    def collection(id_or_name)
      key = id_or_name.to_s
      @record_services[key] ||= Services::RecordService.new(self, key)
    end

    # Creates a new batch handler for transactional multi-requests.
    #
    #   batch = pb.create_batch
    #   batch.collection("posts").create(title: "hello")
    #   batch.collection("posts").update("RECORD_ID", title: "hi")
    #   batch.send
    def create_batch
      Services::BatchService.new(self)
    end

    # Globally enables/disables auto cancellation of duplicated requests.
    # Note: requests are synchronous in the Ruby client, so there is nothing
    # to cancel; the flag is accepted for API compatibility.
    def auto_cancellation(enable)
      @enable_auto_cancellation = !!enable
      self
    end

    # No-op in the synchronous Ruby client (kept for API compatibility).
    def cancel_request(_request_key)
      self
    end

    # No-op in the synchronous Ruby client (kept for API compatibility).
    def cancel_all_requests
      self
    end

    # Builds a filter expression with `{:param}` placeholders populated
    # from params (see Utils.build_filter).
    def filter(raw, params = nil)
      Utils.build_filter(raw, params)
    end

    # Builds a full client URL by safely concatenating the given path.
    def build_url(path = nil)
      url = @base_url.dup
      if path && !path.to_s.empty?
        url += "/" unless url.end_with?("/")
        p = path.to_s
        p = p[1..] if p.start_with?("/")
        url += p
      end
      url
    end

    # Sends an API HTTP request.
    #
    # Options:
    #   method:  "GET" (default), "POST", "PATCH", "PUT", "DELETE", ...
    #   headers: Hash of request headers
    #   body:    Hash (sent as JSON, or as multipart when it has file values),
    #            a PocketBase::MultipartBody, or a raw String
    #   query:   Hash of query params (merged with legacy :params)
    #   timeout: request timeout in seconds
    #   Any other top-level option is moved into the query string.
    #
    # The before_send hook receives (url, options) and may return a Hash with
    # symbol or string keys for url/options; nil preserves current options.
    # The after_send hook receives (ResponseInfo, parsed_data, options), and
    # its return value becomes the result, including the API error payload.
    # Redirects drop credentials across origins. POST becomes GET on 301/302;
    # non-GET/HEAD becomes GET on 303. Other redirects retain method and body.
    #
    # @param path [String] API path relative to base_url
    # @param options [Hash] Request options and extra query parameters
    # @return [Hash, Array, nil] Parsed JSON, nil for an empty body, or hook result
    # @raise [ClientResponseError] On transport errors or HTTP status >= 400
    # @example Request health with a timeout
    #   client.send_request("/api/health", timeout: 10)
    #
    # Raises PocketBase::ClientResponseError on transport or API errors.
    def send_request(path, options = {})
      options = init_send_options(options)
      url = build_url(path)

      if @before_send
        result = @before_send.call(url, options)
        result = normalize_hook_result(result)
        url = result[:url] if result[:url]
        options = result[:options] if result[:options]
      end

      query = options.delete(:query)
      if query && !query.empty?
        serialized = Utils.serialize_query_params(query)
        url += (url.include?("?") ? "&" : "?") + serialized unless serialized.empty?
      end

      method = (options[:method] || "GET").to_s.upcase
      headers = options[:headers] || {}
      body, content_type = prepare_body(options[:body], headers)
      headers = headers.dup
      headers["Content-Type"] = content_type if content_type && !header_present?(headers, "Content-Type")
      timeout = options[:timeout]

      final_url = url
      response = perform_request(url, method, headers, body, timeout) do |u|
        final_url = u
      end

      data = parse_response_body(response)

      if @after_send
        data = @after_send.call(ResponseInfo.new(response, final_url), data, options)
      end

      if response.code.to_i >= 400
        raise ClientResponseError.new(
          url: final_url,
          status: response.code.to_i,
          response: data.is_a?(Hash) ? data : {},
          original_error: nil
        )
      end

      data
    rescue ClientResponseError
      raise
    rescue StandardError => e
      raise ClientResponseError.wrap(e, url: url.to_s)
    end

    # Registers token auto-refresh for superuser sessions, mirroring the
    # js-sdk autoRefreshThreshold behavior: before each request the token is
    # refreshed when it expires within `threshold` seconds, falling back to
    # re-authentication when refresh fails.
    def register_auto_refresh(threshold, refresh_func, reauthenticate_func)
      reset_auto_refresh

      old_before_send = @before_send
      old_record = @auth_store.record

      unsub = @auth_store.on_change do |new_token, model|
        if new_token.to_s.empty? || model_id(model) != model_id(old_record) ||
           (collection_id_of(model) || collection_id_of(old_record)) &&
             collection_id_of(model) != collection_id_of(old_record)
          reset_auto_refresh
        end
      end

      reset_fn = lambda do
        unsub.call
        @before_send = old_before_send
        remove_instance_variable(:@_reset_auto_refresh) if defined?(@_reset_auto_refresh)
      end
      @_reset_auto_refresh = reset_fn

      @before_send = lambda do |url, send_options|
        old_token = @auth_store.token
        query = send_options[:query] || {}

        unless query[:autoRefresh] || query["autoRefresh"]
          is_valid = @auth_store.valid?
          if is_valid && Utils.token_expired?(@auth_store.token, threshold)
            begin
              refresh_func.call
            rescue StandardError
              is_valid = false
            end
          end
          reauthenticate_func.call unless is_valid

          headers = (send_options[:headers] || {}).dup
          headers.each do |k, v|
            if k.to_s.downcase == "authorization" && v == old_token && !@auth_store.token.empty?
              headers[k] = @auth_store.token
              break
            end
          end
          send_options = send_options.merge(headers: headers)
        end

        if old_before_send
          old_before_send.call(url, send_options)
        else
          { url: url, options: send_options }
        end
      end
      self
    end

    def reset_auto_refresh
      @_reset_auto_refresh&.call
      self
    end

    private

    def model_id(model)
      model.is_a?(Hash) ? (model["id"] || model[:id]) : nil
    end

    def collection_id_of(model)
      model.is_a?(Hash) ? (model["collectionId"] || model[:collectionId]) : nil
    end

    def normalize_hook_result(result)
      return {} if result.nil?
      if result.is_a?(Hash) && (result.key?(:url) || result.key?("url") ||
                               result.key?(:options) || result.key?("options"))
        return { url: result[:url] || result["url"], options: result[:options] || result["options"] }
      end

      # legacy behavior: the whole result replaces the options
      { options: result }
    end

    def init_send_options(options)
      normalized = {}
      (options || {}).each { |k, v| normalized[k.to_sym] = v }
      options = { method: "GET" }.merge(normalized)

      # merge legacy :params into :query
      query = {}
      query.merge!(options.delete(:params)) if options[:params]
      query.merge!(options.delete(:query)) if options[:query]

      # move unknown send options into the query (js-sdk compatibility)
      options.keys.each do |key|
        next if KNOWN_SEND_OPTIONS.include?(key.to_sym)

        query[key] = options.delete(key)
      end
      options[:query] = query

      headers = {}
      (options[:headers] || {}).each { |k, v| headers[k.to_s] = v }

      # default json content type unless the body needs multipart
      body = options[:body]
      unless header_present?(headers, "Content-Type") || body.is_a?(MultipartBody) ||
             (body.is_a?(Hash) && Multipart.has_file_field?(body))
        headers["Content-Type"] = "application/json"
      end

      headers["Accept-Language"] = @lang unless header_present?(headers, "Accept-Language")

      if @auth_store.token && !@auth_store.token.empty? && !header_present?(headers, "Authorization")
        headers["Authorization"] = @auth_store.token
      end

      options[:headers] = headers
      options
    end

    def header_present?(headers, name)
      headers.keys.any? { |k| k.to_s.downcase == name.downcase }
    end

    def prepare_body(body, headers)
      return [nil, nil] if body.nil?

      if body.is_a?(MultipartBody)
        return [body.to_s, body.content_type]
      end

      if body.is_a?(Hash) && Multipart.has_file_field?(body)
        form = Multipart.build(body)
        return [form.to_s, form.content_type]
      end

      ct = nil
      headers.each { |k, v| ct = v if k.to_s.downcase == "content-type" }
      if (ct.nil? || ct.include?("application/json")) && !body.is_a?(String)
        return [JSON.generate(body), "application/json"]
      end

      [body.to_s, nil]
    end

    def parse_response_body(response)
      raw = response.body
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue StandardError
      {}
    end

    def perform_request(url, method, headers, body, timeout, redirects = 5, &url_tracker)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      if timeout
        http.open_timeout = timeout
        http.read_timeout = timeout
      end

      request_class = {
        "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post,
        "PUT" => Net::HTTP::Put, "PATCH" => Net::HTTP::Patch,
        "DELETE" => Net::HTTP::Delete, "HEAD" => Net::HTTP::Head,
        "OPTIONS" => Net::HTTP::Options,
      }[method] || Net::HTTP::Get

      req = request_class.new(uri.request_uri)
      headers.each { |k, v| req[k.to_s] = v.to_s }
      req.body = body if body

      response = http.request(req)

      case response
      when Net::HTTPRedirection
        raise ClientResponseError.new(url: url, status: response.code.to_i, response: {}) if redirects <= 0

        location = response["location"]
        target = URI.join(url, location)
        new_url = target.to_s
        if [uri.scheme, uri.host, uri.port] != [target.scheme, target.host, target.port]
          headers = headers.reject { |key, _| %w[authorization cookie proxy-authorization].include?(key.to_s.downcase) }
        end
        url_tracker&.call(new_url)
        switch_to_get = (%w[301 302].include?(response.code) && method == "POST") ||
                        (response.code == "303" && !%w[GET HEAD].include?(method))
        new_method = switch_to_get ? "GET" : method
        if switch_to_get
          body = nil
          headers = headers.reject { |key, _| %w[content-type content-length transfer-encoding].include?(key.to_s.downcase) }
        end
        perform_request(new_url, new_method, headers, body,
                        timeout, redirects - 1, &url_tracker)
      else
        response
      end
    end
  end

  # Lightweight response view passed to the after_send hook.
  class ResponseInfo
    attr_reader :status, :headers, :url

    def initialize(net_response, url)
      @status = net_response.code.to_i
      @headers = {}
      net_response.each_header { |k, v| @headers[k] = v }
      @url = url
    end
  end
end
