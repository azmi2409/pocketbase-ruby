# frozen_string_literal: true

require_relative "pocketbase/version"
require_relative "pocketbase/utils"
require_relative "pocketbase/client_response_error"
require_relative "pocketbase/multipart"
require_relative "pocketbase/auth_store"
require_relative "pocketbase/services/base_service"
require_relative "pocketbase/services/crud_service"
require_relative "pocketbase/services/realtime_service"
require_relative "pocketbase/services/record_service"
require_relative "pocketbase/services/collection_service"
require_relative "pocketbase/services/file_service"
require_relative "pocketbase/services/log_service"
require_relative "pocketbase/services/settings_service"
require_relative "pocketbase/services/backup_service"
require_relative "pocketbase/services/health_service"
require_relative "pocketbase/services/cron_service"
require_relative "pocketbase/services/sql_service"
require_relative "pocketbase/services/batch_service"
require_relative "pocketbase/client"

# Ruby SDK for PocketBase (port of the official pocketbase/js-sdk).
#
#   require "pocketbase"
#
#   pb = PocketBase.new("http://127.0.0.1:8090")
#   pb.collection("users").auth_with_password("test@example.com", "1234567890")
#   pb.collection("posts").get_list(1, 30, filter: "published = true")
module PocketBase
  # Shortcut for PocketBase::Client.new
  def self.new(base_url = "/", auth_store: nil, lang: "en-US")
    Client.new(base_url, auth_store: auth_store, lang: lang)
  end
end
