# frozen_string_literal: true

require "json"

module PocketBase
  # In-memory auth store mirroring the js-sdk BaseAuthStore.
  class AuthStore
    DEFAULT_COOKIE_KEY = "pb_auth"
    # crc32 checksum id of the _superusers collection (fallback check, as in js-sdk)
    SUPERUSERS_COLLECTION_ID = "pbc_3142635823"

    attr_reader :token, :record

    def initialize(token = nil, record = nil)
      @token = ""
      @record = nil
      @on_change_callbacks = []
      save(token, record) if token || record
    end

    # Saves the token and record model, triggering on_change callbacks.
    def save(token, record = nil)
      @token = token.to_s
      @record = record
      trigger_change
      self
    end

    # Clears the stored token and record, triggering on_change callbacks.
    def clear
      @token = ""
      @record = nil
      trigger_change
      self
    end

    # Loosely checks whether the store holds a non-expired token.
    def valid?
      !Utils.token_expired?(@token)
    end

    # Loosely checks whether the stored state belongs to a superuser.
    def superuser?
      payload = Utils.token_payload(@token)
      return false unless payload["type"] == "auth"

      collection_name = @record.is_a?(Hash) ? (@record["collectionName"] || @record[:collectionName]) : nil
      return true if collection_name == "_superusers"
      return true if collection_name.nil? && payload["collectionId"] == SUPERUSERS_COLLECTION_ID

      false
    end

    # Loosely checks whether the stored state belongs to a regular auth record.
    def auth_record?
      Utils.token_payload(@token)["type"] == "auth" && !superuser?
    end

    # Registers a callback invoked on every store change with (token, record).
    # Returns an unsubscribe lambda. Pass fire_immediately: true to invoke
    # the callback right away with the current state.
    def on_change(fire_immediately: false, &callback)
      raise ArgumentError, "callback block required" unless callback

      @on_change_callbacks << callback
      callback.call(@token, @record) if fire_immediately
      -> { @on_change_callbacks.delete(callback) }
    end

    # Parses a cookie string and loads the token/record stored under `key`.
    # (Does not validate the token, same as the js-sdk.)
    def load_from_cookie(cookie, key = DEFAULT_COOKIE_KEY)
      raw = parse_cookie(cookie)[key.to_s] || ""
      data = {}
      begin
        parsed = JSON.parse(Utils.decode_uri_component(raw))
        data = parsed if parsed.is_a?(Hash)
      rescue StandardError
        data = {}
      end
      save(data["token"] || data[:token] || "", data["record"] || data["model"] || data[:record] || data[:model])
    end

    # Exports the current store state as a cookie string.
    # Supported options: :secure, :http_only, :same_site, :path, :domain,
    # :expires (Time), :max_age (seconds).
    def export_to_cookie(options = {}, key = DEFAULT_COOKIE_KEY)
      opts = {
        secure: true,
        http_only: true,
        same_site: "Strict",
        path: "/",
      }.merge(options)

      payload = Utils.token_payload(@token)
      opts[:expires] ||= payload["exp"] ? Time.at(payload["exp"].to_i) : Time.at(0)

      raw_data = {
        "token" => @token,
        "record" => @record ? JSON.parse(JSON.generate(@record)) : nil,
      }

      result = serialize_cookie(key, JSON.generate(raw_data), opts)

      # strip the model down to the bare minimum if the cookie is too large
      if raw_data["record"] && result.bytesize > 4096
        rec = raw_data["record"]
        raw_data["record"] = {
          "id" => rec["id"],
          "email" => rec["email"],
          "collectionId" => rec["collectionId"],
          "collectionName" => rec["collectionName"],
          "verified" => rec["verified"],
        }.compact
        result = serialize_cookie(key, JSON.generate(raw_data), opts)
      end

      result
    end

    private

    def trigger_change
      @on_change_callbacks.each { |cb| cb&.call(@token, @record) }
    end

    def parse_cookie(cookie)
      result = {}
      cookie.to_s.split(";").each do |pair|
        k, v = pair.strip.split("=", 2)
        next if k.nil? || k.empty?

        result[k] = v || ""
      end
      result
    end

    def serialize_cookie(key, value, options)
      parts = ["#{key}=#{Utils.encode_uri_component(value)}"]
      parts << "Path=#{options[:path]}" if options[:path]
      parts << "Domain=#{options[:domain]}" if options[:domain]
      parts << "Expires=#{options[:expires].utc.strftime("%a, %d %b %Y %H:%M:%S GMT")}" if options[:expires]
      parts << "Max-Age=#{options[:max_age].to_i}" if options[:max_age]
      parts << "Secure" if options[:secure]
      parts << "HttpOnly" if options[:http_only]
      same_site = options[:same_site]
      parts << "SameSite=#{same_site == true ? "Strict" : same_site}" if same_site
      parts.join("; ")
    end
  end

  # File-persisted auth store (the Ruby equivalent of js-sdk's LocalAuthStore,
  # which uses browser localStorage). State is stored as JSON at `path`.
  class FileAuthStore < AuthStore
    attr_reader :path

    def initialize(path, token = nil, record = nil)
      @path = path.to_s
      super()
      if token || record
        save(token, record)
      else
        load_from_file
      end
    end

    def save(token, record = nil)
      super
      persist_to_file
      self
    end

    def clear
      super
      persist_to_file
      self
    end

    private

    def load_from_file
      return unless File.exist?(@path)

      data = JSON.parse(File.read(@path))
      @token = data["token"].to_s
      @record = data["record"]
    rescue StandardError
      @token = ""
      @record = nil
    end

    def persist_to_file
      File.write(@path, JSON.generate({ "token" => @token, "record" => @record }))
    rescue StandardError
      nil
    end
  end
end
