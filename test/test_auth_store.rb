# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TestAuthStore < Minitest::Test
  def test_save_and_clear
    store = PocketBase::AuthStore.new
    assert_equal "", store.token
    assert_nil store.record
    refute store.valid?

    store.save("tok123", { "id" => "abc" })
    assert_equal "tok123", store.token
    assert_equal({ "id" => "abc" }, store.record)

    store.clear
    assert_equal "", store.token
    assert_nil store.record
  end

  def test_validity_uses_exp_claim
    store = PocketBase::AuthStore.new
    store.save("eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig", {})
    assert store.valid?

    store.save("eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig", {})
    refute store.valid?
  end

  def test_superuser_detection
    store = PocketBase::AuthStore.new
    token = "eyJhbGciOiJIUzI1NiJ9.eyJ0eXBlIjoiYXV0aCJ9.sig" # {"type":"auth"}, no exp -> valid
    store.save(token, { "collectionName" => "_superusers", "id" => "1" })
    assert store.valid?
    assert store.superuser?
    refute store.auth_record?

    store.save(token, { "collectionName" => "users", "id" => "2" })
    refute store.superuser?
    assert store.auth_record?
  end

  def test_on_change_callbacks
    store = PocketBase::AuthStore.new
    seen = []
    unsub = store.on_change { |t, r| seen << [t, r] }
    store.save("t1", { "id" => "1" })
    assert_equal [["t1", { "id" => "1" }]], seen

    unsub.call
    store.save("t2", nil)
    assert_equal 1, seen.length
  end

  def test_on_change_fire_immediately
    store = PocketBase::AuthStore.new("tok", { "id" => "x" })
    seen = []
    store.on_change(fire_immediately: true) { |t, r| seen << [t, r] }
    assert_equal [["tok", { "id" => "x" }]], seen
  end

  def test_callback_removal_does_not_skip_next_listener
    store = PocketBase::AuthStore.new
    seen = []
    unsubscribe = store.on_change { unsubscribe.call }
    store.on_change { |token, _| seen << token }
    store.save("first")
    store.save("second")
    assert_equal ["first", "second"], seen
  end

  def test_file_store_expands_home_and_reports_write_failure
    Dir.mktmpdir do |dir|
      old_home = ENV["HOME"]
      begin
        ENV["HOME"] = dir
        PocketBase::FileAuthStore.new("~/auth.json").save("token")
        assert_equal "token", PocketBase::FileAuthStore.new(File.join(dir, "auth.json")).token
        assert_raises(Errno::ENOENT) do
          PocketBase::FileAuthStore.new(File.join(dir, "missing", "auth.json")).save("token")
        end
      ensure
        ENV["HOME"] = old_home
      end
    end
  end

  def test_cookie_roundtrip
    store = PocketBase::AuthStore.new
    token = "eyJhbGciOiJIUzI1NiJ9.eyJ0eXBlIjoiYXV0aCIsImV4cCI6OTk5OTk5OTk5OX0.sig"
    store.save(token, { "id" => "1", "email" => "a@b.c" })

    cookie = store.export_to_cookie
    assert_match(/\Apb_auth=/, cookie)
    assert_match(/HttpOnly/, cookie)

    other = PocketBase::AuthStore.new
    other.load_from_cookie(cookie)
    assert_equal token, other.token
    assert_equal "1", other.record["id"]
    assert_equal "a@b.c", other.record["email"]
  end

  def test_file_auth_store_persists
    Dir.mktmpdir do |dir|
      path = File.join(dir, "auth.json")
      store = PocketBase::FileAuthStore.new(path)
      store.save("tok123", { "id" => "abc" })

      loaded = PocketBase::FileAuthStore.new(path)
      assert_equal "tok123", loaded.token
      assert_equal "abc", loaded.record["id"]

      loaded.clear
      reloaded = PocketBase::FileAuthStore.new(path)
      assert_equal "", reloaded.token
    end
  end
end
