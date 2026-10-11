# frozen_string_literal: true

module PocketBase
  module Services
    # Base class for all API services (port of js-sdk BaseService).
    class BaseService
      attr_reader :client

      # Send-level option keys; anything else in an options hash is treated
      # as a query parameter (mirrors js-sdk normalizeUnknownQueryParams).
      SEND_OPTION_KEYS = %i[
        method headers body query params request_key timeout
      ].freeze

      def initialize(client)
        @client = client
      end

      private

      # Builds the options hash for Client#send_request:
      # merges defaults with user options, folds :params into :query and
      # moves unknown top-level keys into :query.
      def send_options(defaults = {}, options = {})
        normalized = {}
        (options || {}).each { |k, v| normalized[k.to_sym] = v }
        opts = defaults.merge(normalized)
        query = {}
        query.merge!(stringify_top(opts.delete(:params))) if opts[:params]
        query.merge!(stringify_top(opts.delete(:query))) if opts[:query]

        opts.keys.each do |key|
          next if SEND_OPTION_KEYS.include?(key.to_sym)

          query[key] = opts.delete(key)
        end

        opts[:query] = query unless query.empty?
        opts
      end

      def stringify_top(hash)
        result = {}
        (hash || {}).each { |k, v| result[k] = v }
        result
      end
    end
  end
end
