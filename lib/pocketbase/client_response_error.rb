# frozen_string_literal: true

require "net/http"

module PocketBase
  # Wraps and normalizes any error raised by Client#send_request,
  # mirroring the js-sdk ClientResponseError.
  class ClientResponseError < StandardError
    attr_reader :url, :status, :response, :original_error
    attr_accessor :is_abort

    def initialize(err_data = nil)
      @url = ""
      @status = 0
      @response = {}
      @is_abort = false
      @original_error = nil

      if err_data.is_a?(Hash)
        @original_error = err_data[:original_error] || err_data["originalError"] || err_data["original_error"]
        @url = err_data[:url] || err_data["url"] || ""
        @status = err_data[:status] || err_data["status"] || 0
        @is_abort = !!(err_data[:is_abort] || err_data["isAbort"] || err_data["is_abort"])
        resp = err_data[:response] || err_data["response"] ||
               err_data[:data] || err_data["data"]
        @response = resp.is_a?(Hash) ? resp : {}
      elsif err_data.is_a?(ClientResponseError)
        @original_error = err_data.original_error
        @url = err_data.url
        @status = err_data.status
        @response = err_data.response
        @is_abort = err_data.is_abort
      elsif !err_data.nil?
        @original_error = err_data
      end

      @original_error ||= err_data unless err_data.is_a?(ClientResponseError) || err_data.is_a?(Hash)

      msg = @response["message"] || @response[:message]
      if msg.nil? && err_data.is_a?(Hash)
        msg = err_data[:message] || err_data["message"]
      end
      msg ||= if @is_abort
                "The request was aborted."
              elsif @original_error.is_a?(SystemCallError) || connection_refused?(@original_error)
                "Failed to connect to the PocketBase server."
              else
                "Something went wrong."
              end

      super(msg.to_s)
    end

    # Alias for #response (backward compatibility with the js-sdk `.data`).
    def data
      @response
    end

    def to_h
      {
        "url" => @url,
        "status" => @status,
        "response" => @response,
        "isAbort" => @is_abort,
        "message" => message,
      }
    end

    # Wraps any raised error into a ClientResponseError (no-op if already one).
    def self.wrap(err, url: "", status: 0)
      return err if err.is_a?(ClientResponseError)

      data = {}
      unless connection_error?(err)
        data = { "message" => err.message } if err.respond_to?(:message) && err.message && !err.message.empty?
      end
      new({ url: url, status: status, response: data, original_error: err })
    end

    # Loose check for transport-level connection failures.
    def self.connection_error?(err)
      return true if err.is_a?(SystemCallError)
      return true if err.is_a?(Net::OpenTimeout) || err.is_a?(Net::ReadTimeout)

      msg = err.respond_to?(:message) ? err.message.to_s : ""
      msg.include?("ECONNREFUSED") || msg.include?("connection refused") ||
        msg.include?("Failed to open TCP connection")
    end

    private

    def connection_refused?(err)
      self.class.connection_error?(err)
    end
  end
end
