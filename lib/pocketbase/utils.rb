# frozen_string_literal: true

require "base64"
require "cgi"
require "json"
require "time"
require "date"

module PocketBase
  # Shared helpers mirroring the js-sdk tools (jwt, options, filter).
  module Utils
    module_function

    # Matches JavaScript's encodeURIComponent (does NOT escape A-Za-z0-9 -_.!~*'()).
    def encode_uri_component(str)
      str.to_s.gsub(/[^A-Za-z0-9\-_.!~*'()]/) do |c|
        c.bytes.map { |b| format("%%%02X", b) }.join
      end
    end

    def decode_uri_component(str)
      CGI.unescape(str.to_s.gsub("+", "%2B"))
    end

    # --- JWT ---------------------------------------------------------------

    # Returns the payload of a JWT token as a Hash ({} when invalid).
    def token_payload(token)
      return {} if token.nil? || token.to_s.empty?

      segment = token.to_s.split(".")[1]
      return {} if segment.nil? || segment.empty?

      padded = segment + ("=" * ((4 - (segment.length % 4)) % 4))
      JSON.parse(Base64.urlsafe_decode64(padded)) || {}
    rescue StandardError
      {}
    end

    # Checks whether a JWT token is expired.
    # Tokens without an `exp` claim are considered valid;
    # empty/invalid tokens are considered expired.
    # `threshold` is subtracted from `exp` (in seconds).
    def token_expired?(token, threshold = 0)
      payload = token_payload(token)
      return true if payload.empty?

      exp = payload["exp"]
      return false if exp.nil?

      exp.to_f - threshold <= Time.now.to_f
    end

    # --- Query params (mirrors js-sdk serializeQueryParams) -----------------

    def serialize_query_params(params)
      parts = []
      (params || {}).each do |key, value|
        values = value.is_a?(Array) ? value : [value]
        values.each do |v|
          v = prepare_query_param_value(v)
          next if v.nil?

          parts << "#{encode_uri_component(key.to_s)}=#{v}"
        end
      end
      parts.join("&")
    end

    def prepare_query_param_value(value)
      return nil if value.nil?

      case value
      when Time, DateTime
        encode_uri_component(value.utc.iso8601(3).sub("T", " "))
      when Date
        encode_uri_component(value.strftime("%Y-%m-%d"))
      when Hash, Array
        encode_uri_component(JSON.generate(value))
      when TrueClass, FalseClass, Numeric
        encode_uri_component(value.to_s)
      else
        encode_uri_component(value.to_s)
      end
    end

    # --- Filter builder (mirrors js-sdk Client#filter) ---------------------

    # Constructs a filter expression with placeholders populated from params.
    #
    # Placeholders use the `{:paramName}` notation:
    #   pb.filter('title ~ {:title} && created >= {:created}',
    #             title: "hello", created: Time.now)
    def build_filter(raw, params = nil)
      return raw.to_s if params.nil? || params.empty?

      mapping = {}
      params.each { |k, v| mapping["{:#{k}}"] = stringify_filter_param(v) }
      return raw.to_s if mapping.empty?

      pattern = Regexp.union(mapping.keys)
      raw.to_s.gsub(pattern) { |m| mapping[m] }
    end

    def stringify_filter_param(val)
      case val
      when TrueClass, FalseClass, Numeric
        val.to_s
      when String
        JSON.generate(val)
      when Time, DateTime
        JSON.generate(val.utc.iso8601(3).sub("T", " "))
      when Date
        JSON.generate(val.strftime("%Y-%m-%d"))
      when NilClass
        "null"
      else
        s = JSON.generate(val)
        s = JSON.generate(s) if s.start_with?("[", "{")
        s
      end
    end

    # Very small URL query-string replacement helper (mirrors the js-sdk
    # private _replaceQueryParams used for the OAuth2 auth URL).
    def replace_query_params(url, replacements = {})
      path, query = url.to_s.split("?", 2)
      parsed = {}
      (query || "").split("&").each do |param|
        next if param.empty?

        k, v = param.split("=", 2)
        parsed[decode_uri_component(k)] = decode_uri_component(v || "")
      end
      replacements.each do |k, v|
        if v.nil?
          parsed.delete(k.to_s)
        else
          parsed[k.to_s] = v.to_s
        end
      end
      rebuilt = parsed.map { |k, v| "#{encode_uri_component(k)}=#{encode_uri_component(v)}" }.join("&")
      rebuilt.empty? ? path : "#{path}?#{rebuilt}"
    end
  end
end
