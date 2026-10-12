# frozen_string_literal: true

require_relative "test_helper"
require "socket"

class TestRealtimeOffline < Minitest::Test
  def with_realtime_server(fail_first: false, close_stream: nil)
    server = TCPServer.new("127.0.0.1", 0)
    requests = Queue.new
    workers = []
    posts = 0
    acceptor = Thread.new do
      loop do
        socket = server.accept
        workers << Thread.new(socket) do |connection|
          begin
            method = connection.gets.split.first
            headers = {}
            while (line = connection.gets) && line != "\r\n"
              key, value = line.split(":", 2)
              headers[key.downcase] = value.strip
            end
            if method == "GET"
              connection.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
              connection.write("event: PB_CONNECT\nid: client-id\ndata: {}\n\n")
              close_stream ? close_stream.pop : connection.read
            else
              body = JSON.parse(connection.read(headers.fetch("content-length").to_i))
              requests << body
              posts += 1
              status = fail_first && posts == 1 ? "400 Bad Request" : "200 OK"
              connection.write("HTTP/1.1 #{status}\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
            end
          ensure
            connection.close
          end
        end
      end
    end
    client = PocketBase.new("http://127.0.0.1:#{server.addr[1]}")
    yield client, requests
  ensure
    client&.realtime&.disconnect
    acceptor&.kill&.join
    server&.close
    workers&.each { |worker| worker.kill.join }
  end

  def test_subscription_normalizes_options_and_stops_idle_reader
    with_realtime_server do |client, requests|
      options = { "params" => { "fields" => "id" }, "filter" => "published = true", "expand" => "author" }
      unsubscribe = client.collection("posts").subscribe("*", options) { |_| }
      key = Timeout.timeout(2) { requests.pop }["subscriptions"].first
      payload = JSON.parse(URI.decode_www_form(key.split("?", 2).last).to_h.fetch("options"))
      assert_equal({ "fields" => "id", "filter" => "published = true", "expand" => "author" }, payload["query"])
      reader = client.realtime.instance_variable_get(:@reader_thread)
      Timeout.timeout(2) { unsubscribe.call }
      refute reader.alive?, "idle SSE reader must terminate on unsubscribe"
      refute client.realtime.connected?
      client.collection("posts").subscribe("*") { |_| }
      assert client.realtime.connected?
      refute_same reader, client.realtime.instance_variable_get(:@reader_thread)
    end
  end

  def test_network_interruption_clears_connection_and_notifies
    close_stream = Queue.new
    with_realtime_server(close_stream: close_stream) do |client, requests|
      disconnected = Queue.new
      client.realtime.on_disconnect = ->(keys) { disconnected << [keys, client.realtime.connected?] }
      client.collection("posts").subscribe("*") { |_| }
      Timeout.timeout(2) { requests.pop }
      close_stream << true
      assert_equal [["posts/*"], false], Timeout.timeout(2) { disconnected.pop }
      assert_equal ["posts/*"], Timeout.timeout(2) { requests.pop }["subscriptions"]
      assert client.realtime.connected?
    end
  end

  def test_failed_subscription_can_be_retried_without_leaking_listener
    with_realtime_server(fail_first: true) do |client, requests|
      assert_raises(PocketBase::ClientResponseError) do
        client.collection("posts").subscribe("*") { |_| }
      end
      client.collection("posts").subscribe("*") { |_| }
      first = Timeout.timeout(2) { requests.pop }
      second = Timeout.timeout(2) { requests.pop }
      assert_equal ["posts/*"], first["subscriptions"]
      assert_equal ["posts/*"], second["subscriptions"]
      listeners = client.realtime.instance_variable_get(:@subscriptions).fetch("posts/*")
      assert_equal 1, listeners.size
    end
  end
end
