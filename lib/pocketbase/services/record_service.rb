# frozen_string_literal: true

require "securerandom"
require "thread"
require "timeout"

module PocketBase
  module Services
    # Record/collection-auth service (port of js-sdk RecordService).
    class RecordService < CrudService
      attr_reader :collection_id_or_name

      def initialize(client, collection_id_or_name)
        super(client)
        @collection_id_or_name = collection_id_or_name.to_s
      end

      def base_collection_path
        "/api/collections/#{Utils.encode_uri_component(@collection_id_or_name)}"
      end

      def base_crud_path
        "#{base_collection_path}/records"
      end

      # Whether the service collection is the superusers collection.
      def superusers?
        @collection_id_or_name == "_superusers" || @collection_id_or_name == "_pbc_2773867675"
      end

      # --- Realtime ------------------------------------------------------

      # Subscribes to realtime changes of a topic ("*" or a record id).
      # Returns an unsubscribe lambda.
      #
      #   unsub = pb.collection("posts").subscribe("*") { |e| puts e["action"] }
      #   unsub.call
      def subscribe(topic, options = {}, &callback)
        raise ArgumentError, "topic must be set" if topic.nil? || topic.to_s.empty?
        raise ArgumentError, "callback block required" unless callback

        @client.realtime.subscribe("#{@collection_id_or_name}/#{topic}", options, &callback)
      end

      # Unsubscribes from a topic, or from everything of this collection
      # when no topic is given.
      def unsubscribe(topic = nil)
        if topic
          @client.realtime.unsubscribe("#{@collection_id_or_name}/#{topic}")
        else
          @client.realtime.unsubscribe_by_prefix(@collection_id_or_name)
        end
      end

      # --- CRUD overrides (auth store syncing) ----------------------------

      def update(id, body_params = nil, options = {})
        item = super
        store_record = @client.auth_store.record
        if store_record.is_a?(Hash) && record_id(store_record) == item_id(item) &&
           auth_record_collection?(store_record)
          auth_expand = ((store_record["expand"] || store_record[:expand]) || {}).dup
          auth_record = store_record.merge(item)
          merged_expand = auth_expand.merge(item["expand"] || item[:expand] || {})
          auth_record["expand"] = merged_expand unless merged_expand.empty? && auth_expand.empty?
          @client.auth_store.save(@client.auth_store.token, auth_record)
        end
        item
      end

      def delete(id, options = {})
        success = super
        store_record = @client.auth_store.record
        if success && store_record.is_a?(Hash) && record_id(store_record) == id.to_s &&
           auth_record_collection?(store_record)
          @client.auth_store.clear
        end
        success
      end

      # --- Auth -----------------------------------------------------------

      # Returns all available collection auth methods.
      def list_auth_methods(options = {})
        opts = send_options({ method: "GET", query: { "fields" => "mfa,otp,password,oauth2" } }, options)
        @client.send_request("#{base_collection_path}/auth-methods", opts)
      end

      # Authenticates with username/email + password. On success the client
      # auth store is updated and {token, record, meta} is returned.
      #
      # For the _superusers collection you may pass
      # `auto_refresh_threshold:` (seconds) to auto-refresh the token.
      def auth_with_password(username_or_email, password, options = {})
        auto_refresh_threshold = options.delete(:auto_refresh_threshold)

        if superusers?
          @client.reset_auto_refresh unless options[:autoRefresh] || options["autoRefresh"]
        end

        opts = send_options(
          { method: "POST", body: { "identity" => username_or_email, "password" => password } },
          options
        )
        auth_data = @client.send_request("#{base_collection_path}/auth-with-password", opts)
        auth_data = auth_response(auth_data)

        if auto_refresh_threshold && superusers?
          @client.register_auto_refresh(
            auto_refresh_threshold,
            -> { auth_refresh(autoRefresh: true) },
            -> { auth_with_password(username_or_email, password, options.merge(autoRefresh: true)) }
          )
        end

        auth_data
      end

      # Authenticates with an OAuth2 code (see also #auth_with_oauth2 for the
      # assisted flow and #oauth2_login_url for manual flows).
      def auth_with_oauth2_code(provider, code, code_verifier, redirect_url, create_data = nil, options = {})
        opts = send_options(
          {
            method: "POST",
            body: {
              "provider" => provider.to_s,
              "code" => code,
              "codeVerifier" => code_verifier,
              "redirectURL" => redirect_url,
              "createData" => create_data,
            },
          },
          options
        )
        auth_response(@client.send_request("#{base_collection_path}/auth-with-oauth2", opts))
      end

      # Assisted OAuth2 sign-in: subscribes to the realtime @oauth2 channel,
      # yields the provider sign-in URL to the given block (open it in a
      # browser), waits for the provider redirect, then exchanges the code.
      #
      #   auth_data = pb.collection("users").auth_with_oauth2(provider: "google") do |url|
      #     puts "Open this URL: #{url}"
      #   end
      #
      # Configure `https://yourdomain.com/api/oauth2-redirect` as the redirect
      # URL in the provider dashboard.
      def auth_with_oauth2(provider:, scopes: nil, create_data: nil, redirect_url: nil,
                           timeout: 300, **options, &url_callback)
        raise ArgumentError, "a url_callback block is required" unless url_callback

        info = find_oauth2_provider(provider)
        redirect_url ||= @client.build_url("/api/oauth2-redirect")

        queue = Queue.new
        realtime = @client.realtime
        unsub = realtime.subscribe("@oauth2") { |e| queue << e }

        begin
          replacements = { "state" => realtime.client_id }
          replacements["scope"] = Array(scopes).join(" ") if scopes && !Array(scopes).empty?
          url = Utils.replace_query_params(info["authURL"].to_s + redirect_url.to_s, replacements)
          url_callback.call(url)

          event = Timeout.timeout(timeout) { queue.pop }
          current_state = realtime.client_id
          if event["state"].nil? || event["state"] != current_state
            raise ClientResponseError.new("message" => "State parameters don't match.")
          end
          if event["error"] || !event["code"]
            raise ClientResponseError.new("message" => "OAuth2 redirect error or missing code: #{event["error"]}")
          end

          auth_with_oauth2_code(provider.to_s, event["code"], info["codeVerifier"],
                                redirect_url, create_data, options)
        ensure
          unsub.call
        end
      rescue Timeout::Error
        raise ClientResponseError.new("message" => "OAuth2 flow timed out waiting for the provider redirect.")
      end

      # Builds an OAuth2 sign-in URL for manual flows. Returns a Hash with
      # "url", "state" and "code_verifier" — pass the code_verifier to
      # #auth_with_oauth2_code once you have the provider code.
      def oauth2_login_url(provider, redirect_url: nil, scopes: nil)
        info = find_oauth2_provider(provider)
        redirect_url ||= @client.build_url("/api/oauth2-redirect")
        state = SecureRandom.hex(16)
        replacements = { "state" => state }
        replacements["scope"] = Array(scopes).join(" ") if scopes && !Array(scopes).empty?
        {
          "url" => Utils.replace_query_params(info["authURL"].to_s + redirect_url.to_s, replacements),
          "state" => state,
          "code_verifier" => info["codeVerifier"],
        }
      end

      # Refreshes the current authenticated record, returning a new token.
      def auth_refresh(options = {})
        opts = send_options({ method: "POST" }, options)
        auth_response(@client.send_request("#{base_collection_path}/auth-refresh", opts))
      end

      # Sends a password reset email. Returns true on success.
      def request_password_reset(email, options = {})
        opts = send_options({ method: "POST", body: { "email" => email } }, options)
        @client.send_request("#{base_collection_path}/request-password-reset", opts)
        true
      end

      # Confirms a password reset. Returns true on success.
      def confirm_password_reset(password_reset_token, password, password_confirm, options = {})
        opts = send_options(
          { method: "POST",
            body: { "token" => password_reset_token, "password" => password,
                    "passwordConfirm" => password_confirm } },
          options
        )
        @client.send_request("#{base_collection_path}/confirm-password-reset", opts)
        true
      end

      # Sends a verification email. Returns true on success.
      def request_verification(email, options = {})
        opts = send_options({ method: "POST", body: { "email" => email } }, options)
        @client.send_request("#{base_collection_path}/request-verification", opts)
        true
      end

      # Confirms an email verification. Updates the auth store verified flag
      # when it matches the current auth record. Returns true on success.
      def confirm_verification(verification_token, options = {})
        opts = send_options({ method: "POST", body: { "token" => verification_token } }, options)
        @client.send_request("#{base_collection_path}/confirm-verification", opts)

        payload = Utils.token_payload(verification_token)
        model = @client.auth_store.record
        if model.is_a?(Hash) && !verified?(model) &&
           record_id(model) == payload["id"] && record_collection_id(model) == payload["collectionId"]
          model = model.merge("verified" => true)
          @client.auth_store.save(@client.auth_store.token, model)
        end
        true
      end

      # Sends an email change request to the authenticated record.
      def request_email_change(new_email, options = {})
        opts = send_options({ method: "POST", body: { "newEmail" => new_email } }, options)
        @client.send_request("#{base_collection_path}/request-email-change", opts)
        true
      end

      # Confirms a new email address. Clears the auth store when it matches
      # the current auth record. Returns true on success.
      def confirm_email_change(email_change_token, password, options = {})
        opts = send_options(
          { method: "POST", body: { "token" => email_change_token, "password" => password } },
          options
        )
        @client.send_request("#{base_collection_path}/confirm-email-change", opts)

        payload = Utils.token_payload(email_change_token)
        model = @client.auth_store.record
        if model.is_a?(Hash) && record_id(model) == payload["id"] &&
           record_collection_id(model) == payload["collectionId"]
          @client.auth_store.clear
        end
        true
      end

      # Sends an OTP to the given email. Returns { "otpId" => ... }.
      def request_otp(email, options = {})
        opts = send_options({ method: "POST", body: { "email" => email } }, options)
        @client.send_request("#{base_collection_path}/request-otp", opts)
      end

      # Authenticates with an OTP id + password.
      def auth_with_otp(otp_id, password, options = {})
        opts = send_options(
          { method: "POST", body: { "otpId" => otp_id, "password" => password } },
          options
        )
        auth_response(@client.send_request("#{base_collection_path}/auth-with-otp", opts))
      end

      # Impersonates a record (superusers only). Returns a NEW client loaded
      # with the impersonated auth state.
      def impersonate(record_id, duration = 0, options = {})
        opts = send_options({ method: "POST", body: { "duration" => duration } }, options)
        headers = (opts[:headers] || {}).dup
        headers["Authorization"] ||= @client.auth_store.token
        opts[:headers] = headers

        client = Client.new(@client.base_url, lang: @client.lang)
        auth_data = client.send_request(
          "#{base_collection_path}/impersonate/#{Utils.encode_uri_component(record_id.to_s)}", opts
        )
        client.auth_store.save(auth_data["token"], decode(auth_data["record"] || {}))
        client
      end

      # @deprecated Use collection("_externalAuths") directly.
      def list_external_auths(record_id, options = {})
        @client.collection("_externalAuths").get_full_list(
          options.merge(filter: @client.filter("recordRef = {:id}", id: record_id))
        )
      end

      # @deprecated Use collection("_externalAuths") directly.
      def unlink_external_auth(record_id, provider, options = {})
        ea = @client.collection("_externalAuths").get_first_list_item(
          @client.filter("recordRef = {:recordId} && provider = {:provider}",
                         recordId: record_id, provider: provider)
        )
        @client.collection("_externalAuths").delete(ea["id"], options)
        true
      end

      private

      def auth_response(response_data)
        record = decode(response_data["record"] || response_data[:record] || {})
        @client.auth_store.save(response_data["token"] || response_data[:token], record)
        (response_data || {}).merge("token" => response_data["token"] || response_data[:token] || "",
                                    "record" => record)
      end

      def find_oauth2_provider(provider)
        methods = list_auth_methods
        info = methods.dig("oauth2", "providers")&.find { |p| p["name"] == provider.to_s }
        unless info
          raise ClientResponseError.new("message" => %(Missing or invalid provider "#{provider}".))
        end

        info
      end

      def auth_record_collection?(store_record)
        [store_record["collectionId"], store_record["collectionName"],
         store_record[:collectionId], store_record[:collectionName]]
          .compact.map(&:to_s).include?(@collection_id_or_name)
      end

      def record_id(model)
        (model["id"] || model[:id]).to_s
      end

      def item_id(item)
        ((item["id"] || item[:id]) || "").to_s
      end

      def record_collection(model)
        model["collectionName"] || model[:collectionName] ||
          model["collectionId"] || model[:collectionId]
      end

      def record_collection_id(model)
        model["collectionId"] || model[:collectionId]
      end

      def verified?(model)
        model["verified"] || model[:verified]
      end
    end
  end
end
