# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "thread"
require "timeout"

module PocketBase
  module Services
    # Realtime (SSE) service (port of js-sdk RealtimeService).
    #
    #   unsub = pb.realtime.subscribe("posts/*") { |e| puts e["action"] }
    #   # ...
    #   unsub.call
    #
    # The SSE stream runs in a background thread with automatic reconnect
    # (200ms → 2s backoff, mirroring the js-sdk intervals).
    class RealtimeService < BaseService
      RECONNECT_INTERVALS = [0.2, 0.3, 0.5, 1.0, 1.2, 1.5, 2.0].freeze
      CONNECT_TIMEOUT = 15

      attr_reader :client_id
      # Callback invoked on explicit disconnect or stream interruption.
      # Receives active subscription keys after connection identity is cleared.
      # Runs on the caller thread for disconnect, reader thread for interruption.
      # @return [Proc, nil]
      attr_accessor :on_disconnect

      def initialize(client)
        super
        @client_id = ""
        @subscriptions = {} # key => Array of procs
        @last_sent = []
        @mutex = Mutex.new
        @connect_mutex = Mutex.new
        @submit_mutex = Mutex.new
        @connect_queue = Queue.new
        @awaiting_initial = false
        @reader_thread = nil
        @stop = false
        @connect_gen = 0
        @on_disconnect = nil
      end

      # Whether the realtime SSE connection is established.
      def connected?
        @mutex.synchronize { !@client_id.empty? && @reader_thread&.alive? }
      end

      # Registers a subscription listener for a topic.
      # Returns an unsubscribe lambda removing only this listener.
      # Unknown top-level options (filter, expand, fields) become query options.
      # Failed registration removes this listener and can be retried.
      #
      # @param topic [String] SSE topic, e.g. "posts/*" or "@oauth2"
      # @param options [Hash] Query/params, headers, and extra query options
      # @yield [data] Parsed event data, delivered on the SSE reader thread
      # @yieldparam data [Hash] Event payload
      # @return [Proc] Callable removing only this listener
      # @raise [ArgumentError] If topic or callback is missing
      # @raise [ClientResponseError] If connection or subscription update fails
      # @example Listen for record changes
      #   unsubscribe = client.realtime.subscribe("posts/*") { |event| puts event["action"] }
      #   unsubscribe.call
      def subscribe(topic, options = {}, &callback)
        raise ArgumentError, "topic must be set" if topic.nil? || topic.to_s.empty?
        raise ArgumentError, "callback block required" unless callback

        key = topic.to_s
        unless options.nil? || options.empty?
          options = send_options({}, options)
          payload = {
            "query" => options[:query] || options["query"],
            "headers" => options[:headers] || options["headers"],
          }.compact
          key += (key.include?("?") ? "&" : "?") +
                 "options=#{Utils.encode_uri_component(JSON.generate(payload))}"
        end

        listener = ->(data) { callback.call(data) }
        first_for_key = false
        @mutex.synchronize do
          @subscriptions[key] ||= []
          first_for_key = @subscriptions[key].empty?
          @subscriptions[key] << listener
        end

        begin
          connect unless connected?
          submit_subscriptions if first_for_key && connected?
        rescue StandardError
          @mutex.synchronize do
            @subscriptions[key]&.delete(listener)
            @subscriptions.delete(key) if @subscriptions[key]&.empty?
          end
          disconnect if @mutex.synchronize { @subscriptions.empty? }
          raise
        end

        -> { unsubscribe_listener(topic.to_s, listener) }
      end

      # Unsubscribes from a topic, or from everything when topic is nil.
      # Closes the SSE connection when no subscriptions remain.
      def unsubscribe(topic = nil)
        @mutex.synchronize do
          if topic.nil?
            @subscriptions = {}
          else
            matching_keys(topic.to_s).each { |k| @subscriptions.delete(k) }
          end
        end
        submit_subscriptions
        nil
      end

      # Unsubscribes from all subscriptions starting with the given prefix.
      def unsubscribe_by_prefix(prefix)
        removed = false
        @mutex.synchronize do
          @subscriptions.keys.each do |key|
            if (key + "?").start_with?(prefix.to_s)
              @subscriptions.delete(key)
              removed = true
            end
          end
        end
        submit_subscriptions if removed
        nil
      end

      # Closes the SSE connection (keeps registered subscriptions).
      # Stops and joins the reader, including when the stream is idle.
      # When called from a listener, the reader exits after callback delivery.
      # A later subscription reconnects and restores registered subscriptions.
      #
      # @return [nil]
      def disconnect
        keys = []
        had_client = false
        @mutex.synchronize do
          had_client = !@client_id.empty?
          keys = @subscriptions.keys
          @stop = true
          @client_id = ""
          @last_sent = []
        end
        @on_disconnect&.call(keys) if had_client

        thread = @mutex.synchronize { @reader_thread }
        if thread && thread != Thread.current
          thread.kill
          thread.join
        end
        @mutex.synchronize { @reader_thread = nil if @reader_thread == thread }
        nil
      end

      private

      def stopped?
        @mutex.synchronize { @stop }
      end

      def connect
        @connect_mutex.synchronize do
          return if connected?

          gen = @mutex.synchronize do
            @connect_gen += 1
            @awaiting_initial = true
            @stop = false
            if @reader_thread.nil? || !@reader_thread.alive?
              @reader_thread = Thread.new { reader_loop }
            end
            @connect_gen
          end

          begin
            deadline = Time.now + CONNECT_TIMEOUT
            loop do
              remaining = deadline - Time.now
              if remaining <= 0
                raise ClientResponseError.new("message" => "Realtime connect took too long.")
              end

              item_gen, payload = Timeout.timeout(remaining) { @connect_queue.pop }
              next unless item_gen == gen # ignore stale signals from older connects

              raise payload if payload.is_a?(Exception)

              break
            end
          rescue Timeout::Error
            raise ClientResponseError.new("message" => "Realtime connect took too long.")
          ensure
            @mutex.synchronize { @awaiting_initial = false }
          end

          submit_subscriptions
        end
      end

      def reader_loop
        attempts = 0
        loop do
          break if stopped?

          begin
            stream_sse
          rescue StandardError => e
            gen = @mutex.synchronize { @awaiting_initial ? @connect_gen : nil }
            if gen
              @connect_queue << [gen, e]
              break
            end
          end
          keys = @mutex.synchronize do
            had_client = !@client_id.empty?
            @client_id = ""
            @last_sent = []
            had_client ? @subscriptions.keys : nil
          end
          @on_disconnect&.call(keys) if keys

          break if stopped?

          has_subs = @mutex.synchronize { @subscriptions.any? { |_, v| v.any? } }
          unless has_subs
            @mutex.synchronize { @client_id = ""; @last_sent = [] }
            break
          end

          sleep RECONNECT_INTERVALS[[attempts, RECONNECT_INTERVALS.length - 1].min]
          attempts += 1
          break if stopped?

        end
      end

      def stream_sse
        uri = URI.parse(@client.build_url("/api/realtime"))
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req["Accept"] = "text/event-stream"
          token = @client.auth_store.token
          req["Authorization"] = token unless token.nil? || token.empty?

          http.request(req) do |resp|
            if resp.code.to_i >= 400
              raise ClientResponseError.new(
                "url" => @client.build_url("/api/realtime"),
                "status" => resp.code.to_i,
                "response" => (JSON.parse(resp.body) rescue {})
              )
            end

            buffer = +""
            event = nil
            data_lines = []
            event_id = nil

            resp.read_body do |chunk|
              break if stopped?

              buffer << chunk
              while (idx = buffer.index("\n"))
                line = buffer.slice!(0, idx + 1).chomp
                if line.empty?
                  dispatch_event(event, data_lines.join("\n"), event_id)
                  event = nil
                  data_lines = []
                elsif line.start_with?("event:")
                  event = line[6..].sub(/\A /, "")
                elsif line.start_with?("data:")
                  data_lines << line[5..].sub(/\A /, "")
                elsif line.start_with?("id:")
                  event_id = line[3..].sub(/\A /, "")
                end
                # ":" comment/heartbeat lines are ignored
              end
            end
          end
        end
      end

      def dispatch_event(event, data, event_id)
        if event == "PB_CONNECT"
          @mutex.synchronize do
            @client_id = event_id.to_s
            @last_sent = []
          end
          gen = @mutex.synchronize { @awaiting_initial ? @connect_gen : nil }
          @connect_queue << [gen, :connected] if gen
          deliver("PB_CONNECT", parse_data(data))
          unless gen
            # Reconnect: submit here so the reader loop can back off and
            # retry when the submit fails (a raise aborts the stream and
            # triggers a reconnect in reader_loop).
            #
            # Initial connect: #connect submits synchronously after the
            # queue pop, so subscribe() only returns once the server has
            # confirmed the subscriptions (avoids a create-before-submit race).
            submit_subscriptions
          end
          return
        end

        return if event.nil? || event.empty?

        deliver(event, parse_data(data))
      end

      def deliver(key, data)
        listeners = @mutex.synchronize { (@subscriptions[key] || []).dup }
        listeners.each do |listener|
          begin
            listener.call(data)
          rescue StandardError
            nil
          end
        end
      end

      def parse_data(data)
        JSON.parse(data)
      rescue StandardError
        {}
      end

      def submit_subscriptions
        if @mutex.synchronize { @subscriptions.empty? }
          disconnect
          return
        end

        @submit_mutex.synchronize do
          keys = @mutex.synchronize { @subscriptions.select { |_, v| v.any? }.keys }
          client_id = @mutex.synchronize { @client_id }
          return if client_id.empty?

          last_sent = @mutex.synchronize { @last_sent }
          return if (keys - last_sent).empty? && (last_sent - keys).empty?

          @client.send_request(
            "/api/realtime",
            method: "POST",
            body: { "clientId" => client_id, "subscriptions" => keys }
          )
          @mutex.synchronize { @last_sent = keys if @client_id == client_id }
        end
      rescue ClientResponseError
        raise
      rescue StandardError => e
        raise ClientResponseError.wrap(e)
      end

      def unsubscribe_listener(topic, listener)
        @mutex.synchronize do
          matching_keys(topic).each do |key|
            arr = @subscriptions[key]
            next unless arr

            arr.delete(listener)
            @subscriptions.delete(key) if arr.empty?
          end
        end
        submit_subscriptions
        nil
      end

      def matching_keys(topic)
        t = topic.include?("?") ? topic : topic + "?"
        @subscriptions.keys.select { |k| (k + "?").start_with?(t) }
      end
    end
  end
end
