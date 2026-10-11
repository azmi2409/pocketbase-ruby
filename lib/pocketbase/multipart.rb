# frozen_string_literal: true

require "securerandom"

module PocketBase
  # Minimal multipart/form-data builder (stdlib only).
  class MultipartBody
    attr_reader :boundary

    def initialize(boundary = nil)
      @boundary = boundary || "----PocketBaseRuby#{SecureRandom.hex(16)}"
      @parts = [] # each entry: [headers_array, body_string]
    end

    def add_field(name, value)
      @parts << [
        [["Content-Disposition", %(form-data; name="#{name}")]],
        value.to_s,
      ]
      self
    end

    def add_json_payload(hash)
      add_field("@jsonPayload", JSON.generate(hash))
    end

    def add_file(name, filename, content_type, data)
      @parts << [
        [
          ["Content-Disposition", %(form-data; name="#{name}"; filename="#{filename}")],
          ["Content-Type", content_type || "application/octet-stream"],
        ],
        data.to_s.b,
      ]
      self
    end

    def content_type
      "multipart/form-data; boundary=#{@boundary}"
    end

    def to_s
      # binary accumulator so arbitrary file bytes never raise
      # Encoding::CompatibilityError when appended
      out = "".b
      @parts.each do |headers, body|
        out << "--#{@boundary}\r\n".b
        headers.each { |k, v| out << "#{k}: #{v}\r\n".b }
        out << "\r\n".b
        out << body.to_s.b
        out << "\r\n".b
      end
      out << "--#{@boundary}--\r\n".b
      out
    end
  end

  module Multipart
    module_function

    # A value counts as a file when it is a File/IO object or a
    # { filename:, data: } / { "filename" =>, "data" => } style hash.
    def file_value?(value)
      return true if value.is_a?(File)
      return true if value.is_a?(Hash) && (value.key?(:filename) || value.key?("filename") ||
                                          value.key?(:data) || value.key?("data"))
      return true if value.respond_to?(:read) && !value.is_a?(String)

      false
    end

    def has_file_field?(body)
      return false unless body.is_a?(Hash)

      body.each_value do |val|
        values = val.is_a?(Array) ? val : [val]
        return true if values.any? { |v| file_value?(v) }
      end
      false
    end

    # Mirrors js-sdk convertToFormDataIfNeeded: plain Hash/Array values are
    # sent via @jsonPayload parts to avoid implicit string normalization,
    # files become regular multipart file parts.
    def build(body)
      form = MultipartBody.new
      (body || {}).each do |key, val|
        next if val.nil?

        key = key.to_s
        if val.is_a?(Hash) && !file_value?(val)
          form.add_json_payload({ key => val })
        elsif val.is_a?(Array) && !val.any? { |v| file_value?(v) } && val.any? { |v| v.is_a?(Hash) || v.is_a?(Array) }
          form.add_json_payload({ key => val })
        elsif val.is_a?(Array)
          val.each { |v| append_value(form, key, v) }
        else
          append_value(form, key, val)
        end
      end
      form
    end

    def append_value(form, key, val)
      if file_value?(val)
        info = file_info(val, key)
        form.add_file(key, info[:filename], info[:content_type], info[:data])
      elsif val.is_a?(Hash) || val.is_a?(Array)
        form.add_json_payload({ key => val })
      else
        form.add_field(key, val)
      end
    end

    def file_info(value, default_name = "file")
      case value
      when File
        value.binmode
        {
          filename: File.basename(value.path),
          content_type: nil,
          data: value.read,
        }
      when Hash
        {
          filename: value[:filename] || value["filename"] || default_name,
          content_type: value[:content_type] || value["content_type"],
          data: value[:data] || value["data"],
        }
      else # IO-like (StringIO, Tempfile, ...)
        {
          filename: (value.respond_to?(:path) && value.path ? File.basename(value.path.to_s) : default_name),
          content_type: nil,
          data: value.read,
        }
      end
    end
  end
end
