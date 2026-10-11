# frozen_string_literal: true

require "minitest/autorun"
require "timeout"
require "tmpdir"
require "securerandom"
require_relative "../lib/pocketbase"

PB_URL = ENV.fetch("POCKETBASE_URL", "http://127.0.0.1:8090")
SUPERUSER_EMAIL = "admin@test.com"
SUPERUSER_PASSWORD = "password123"

# 1x1 transparent PNG for upload tests
PNG_BYTES = [
  "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489" \
  "0000000d49444154789c626001000000ffff03000006000557bfabd40000000049" \
  "454e44ae426082"
].pack("H*").b

# Base class for integration tests: fresh superuser-authenticated client,
# idempotent collection setup.
class PocketBaseIntegrationTest < Minitest::Test
  def setup
    @pb = PocketBase.new(PB_URL)
    @pb.collection("_superusers").auth_with_password(SUPERUSER_EMAIL, SUPERUSER_PASSWORD)
    ensure_collections
    ensure_batch_enabled
  end

  def teardown
    @pb.realtime.disconnect if @pb.realtime.connected?
  end

  def pb
    @pb
  end

  private

  # The /api/batch endpoint is disabled by default; enable it once.
  def ensure_batch_enabled
    settings = @pb.settings.get_all
    return if settings["batch"] && settings["batch"]["enabled"]

    settings["batch"] ||= {}
    settings["batch"]["enabled"] = true
    @pb.settings.update(settings)
  end

  def ensure_collections
    ensure_posts_collection
    ensure_users_collection
  end

  def ensure_posts_collection
    existing = @pb.collections.get_first_list_item('name = "posts"')
    return existing
  rescue PocketBase::ClientResponseError
    base = @pb.collections.get_scaffolds["base"].dup
    base["name"] = "posts"
    base["listRule"] = ""
    base["viewRule"] = ""
    base["fields"] = [
      { "name" => "title", "type" => "text", "required" => true },
      { "name" => "views", "type" => "number" },
      { "name" => "image", "type" => "file", "maxSelect" => 1 },
    ]
    @pb.collections.create(base)
  end

  def ensure_users_collection
    existing = @pb.collections.get_first_list_item('name = "users"')
    return existing
  rescue PocketBase::ClientResponseError
    auth = @pb.collections.get_scaffolds["auth"].dup
    auth["name"] = "users"
    auth["listRule"] = ""
    auth["viewRule"] = ""
    @pb.collections.create(auth)
  end

  def unique_title(prefix = "test")
    "#{prefix}-#{SecureRandom.hex(4)}"
  end
end
