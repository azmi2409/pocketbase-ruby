# frozen_string_literal: true

require_relative "test_helper"

class TestAuth < PocketBaseIntegrationTest
  def test_superuser_password_auth
    client = PocketBase.new(PB_URL)
    auth = client.collection("_superusers").auth_with_password(SUPERUSER_EMAIL, SUPERUSER_PASSWORD)

    refute_empty auth["token"]
    assert_equal SUPERUSER_EMAIL, auth["record"]["email"]
    assert_equal auth["token"], client.auth_store.token
    assert client.auth_store.valid?
    assert client.auth_store.superuser?
    refute client.auth_store.auth_record?
  end

  def test_auth_with_wrong_password_raises
    client = PocketBase.new(PB_URL)
    err = assert_raises(PocketBase::ClientResponseError) do
      client.collection("_superusers").auth_with_password(SUPERUSER_EMAIL, "wrong")
    end
    assert_equal 400, err.status
    refute_empty err.message
  end

  def test_auth_refresh
    before = pb.auth_store.token
    auth = pb.collection("_superusers").auth_refresh
    refute_empty auth["token"]
    assert pb.auth_store.valid?
    # refreshed token may occasionally equal the old one if issued within the same second window;
    # the store must at least hold the returned token
    assert_equal auth["token"], pb.auth_store.token
  end

  def test_user_auth_record_flow
    email = "user-#{SecureRandom.hex(4)}@test.com"
    user = pb.collection("users").create(
      "email" => email,
      "password" => SUPERUSER_PASSWORD,
      "passwordConfirm" => SUPERUSER_PASSWORD,
      "verified" => true
    )

    client = PocketBase.new(PB_URL)
    auth = client.collection("users").auth_with_password(email, SUPERUSER_PASSWORD)
    assert_equal user["id"], auth["record"]["id"]
    assert client.auth_store.auth_record?
    refute client.auth_store.superuser?

    # updating the authed record syncs the auth store
    updated = client.collection("users").update(user["id"], "name" => "Tester")
    assert_equal "Tester", client.auth_store.record["name"]

    # deleting the authed record clears the auth store
    client.collection("users").delete(user["id"])
    refute client.auth_store.valid?
    assert_equal "", client.auth_store.token
  end

  def test_impersonate
    email = "imp-#{SecureRandom.hex(4)}@test.com"
    user = pb.collection("users").create(
      "email" => email,
      "password" => SUPERUSER_PASSWORD,
      "passwordConfirm" => SUPERUSER_PASSWORD,
      "verified" => true
    )

    impersonated = pb.collection("users").impersonate(user["id"])
    assert_equal user["id"], impersonated.auth_store.record["id"]
    assert impersonated.auth_store.valid?

    refreshed = impersonated.collection("users").auth_refresh
    assert_equal user["id"], refreshed["record"]["id"]
  ensure
    pb.collection("users").delete(user["id"]) if user
  end

  def test_list_auth_methods_shape
    methods = pb.collection("users").list_auth_methods
    assert methods.key?("password")
    assert methods.key?("oauth2")
    assert_equal true, methods["password"]["enabled"]
  end

  def test_request_password_reset_with_unconfigured_mail
    # No SMTP configured on the test server: PocketBase skips sending
    # and still returns 204.
    assert_equal true, pb.collection("users").request_password_reset("nobody@test.com")
  end

  def test_confirm_verification_with_bad_token_raises
    err = assert_raises(PocketBase::ClientResponseError) do
      pb.collection("users").confirm_verification("bad-token")
    end
    assert_equal 400, err.status
  end

  def test_superuser_auto_refresh_threshold
    client = PocketBase.new(PB_URL)
    client.collection("_superusers").auth_with_password(
      SUPERUSER_EMAIL, SUPERUSER_PASSWORD, auto_refresh_threshold: 999_999_999
    )
    t1 = client.auth_store.token
    sleep 1.1 # tokens issued in the same second are identical
    client.health.check
    assert_operator client.auth_store.token, :!=, t1
    assert client.auth_store.valid?
  ensure
    client.reset_auto_refresh if defined?(client) && client
  end

  def test_oauth2_login_url_with_unknown_provider_raises
    err = assert_raises(PocketBase::ClientResponseError) do
      pb.collection("users").oauth2_login_url("nope")
    end
    assert_match(/Missing or invalid provider/, err.message)
  end
end
