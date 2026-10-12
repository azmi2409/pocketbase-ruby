# frozen_string_literal: true

require_relative "test_helper"
require "socket"

class TestTransport < Minitest::Test
  def with_server(responses)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      responses.each do |status, headers, body|
        socket = server.accept
        begin
          request = { line: socket.gets.strip, headers: {} }
          while (line = socket.gets) && line != "\r\n"
            key, value = line.split(":", 2)
            request[:headers][key.downcase] = value.strip
          end
          length = request[:headers].fetch("content-length", "0").to_i
          request[:body] = length.zero? ? "" : socket.read(length)
          requests << request
          socket.write("HTTP/1.1 #{status}\r\nConnection: close\r\nContent-Length: #{body.bytesize}\r\n")
          headers.each { |key, value| socket.write("#{key}: #{value}\r\n") }
          socket.write("\r\n#{body}")
        ensure
          socket.close
        end
      end
    end
    yield "http://127.0.0.1:#{server.addr[1]}", requests
    thread.value
  ensure
    server&.close
    thread&.kill
    thread&.join
  end

  def test_cross_origin_redirect_does_not_forward_credentials
    with_server([["200 OK", {}, '{"ok":true}']]) do |target, received|
      with_server([["302 Found", { "Location" => target }, ""]]) do |origin, _|
        client = PocketBase.new(origin)
        client.auth_store.save("secret-token")
        assert_equal({ "ok" => true }, client.send_request("/start", headers: { "Cookie" => "session=secret" }))
        refute received.first[:headers].key?("authorization")
        refute received.first[:headers].key?("cookie")
      end
    end
  end

  def test_same_origin_redirect_preserves_credentials_and_put
    with_server([["302 Found", { "Location" => "/end" }, ""], ["200 OK", {}, "{}"]]) do |url, requests|
      client = PocketBase.new(url)
      client.auth_store.save("secret-token")
      client.send_request("/start", method: "PUT", body: { value: 1 })
      assert_equal "PUT /end HTTP/1.1", requests.last[:line]
      assert_equal '{"value":1}', requests.last[:body]
      assert_equal "secret-token", requests.last[:headers]["authorization"]
    end
  end

  def test_redirect_method_and_body_rules
    [["301", "POST", "GET"], ["303", "PATCH", "GET"], ["307", "POST", "POST"], ["308", "PUT", "PUT"]].each do |status, method, expected|
      with_server([["#{status} Redirect", { "Location" => "/end" }, ""], ["200 OK", {}, "{}"]]) do |url, requests|
        PocketBase.new(url).send_request("/start", method: method, body: { value: 1 })
        assert_equal "#{expected} /end HTTP/1.1", requests.last[:line]
        assert_equal(expected == "GET" ? "" : '{"value":1}', requests.last[:body])
        refute requests.last[:headers].key?("content-type") if expected == "GET"
      end
    end
  end

  def test_string_keyed_hook_result_changes_url_and_options
    with_server([["200 OK", {}, "{}"]]) do |url, requests|
      client = PocketBase.new(url)
      client.before_send = lambda do |_url, options|
        { "url" => "#{url}/changed", "options" => options.merge(method: "POST", body: { value: 2 }) }
      end
      client.send_request("/original")
      assert_equal "POST /changed HTTP/1.1", requests.first[:line]
      assert_equal '{"value":2}', requests.first[:body]
    end
  end

  def test_nil_hook_result_preserves_request_options
    with_server([["200 OK", {}, "{}"]]) do |url, requests|
      client = PocketBase.new(url)
      client.before_send = ->(_url, _options) { nil }
      client.send_request("/start", method: "POST", body: { value: 3 })
      assert_equal "POST /start HTTP/1.1", requests.first[:line]
      assert_equal '{"value":3}', requests.first[:body]
    end
  end
end
