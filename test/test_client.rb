# frozen_string_literal: true

require_relative "test_helper"

class TestClient < PocketBaseIntegrationTest
  def test_health_check
    result = pb.health.check
    assert_equal 200, result["code"]
    assert_equal "API is healthy.", result["message"]
  end

  def test_send_request_directly
    result = pb.send_request("/api/health", method: "GET")
    assert_equal 200, result["code"]
  end

  def test_send_request_with_string_keys
    result = pb.send_request("/api/health", "method" => "GET")
    assert_equal 200, result["code"]
  end

  def test_build_url
    assert_equal "http://127.0.0.1:8090/api/health", pb.build_url("/api/health")
    assert_equal "http://127.0.0.1:8090/api/health", pb.build_url("api/health")
  end

  def test_filter_helper
    assert_equal 'a = "x"', pb.filter("a = {:v}", v: "x")
  end

  def test_before_send_hook
    called = false
    pb.before_send = lambda do |url, options|
      called = true
      { url: url, options: options }
    end
    pb.health.check
    assert called
  ensure
    pb.before_send = nil
  end


  def test_after_send_hook
    pb.after_send = lambda do |response, data, _options|
      assert_equal 200, response.status
      data.merge("hooked" => true)
    end
    result = pb.health.check
    assert_equal true, result["hooked"]
  ensure
    pb.after_send = nil
  end

  def test_client_response_error_on_404
    err = assert_raises(PocketBase::ClientResponseError) do
      pb.collection("posts").get_one("nonexistent-id-000")
    end
    assert_equal 404, err.status
    refute_empty err.message
    assert_equal err.response, err.data
    assert_match(/8090/, err.url)
  end

  def test_get_one_with_empty_id_raises_404
    err = assert_raises(PocketBase::ClientResponseError) { pb.collection("posts").get_one("") }
    assert_equal 404, err.status
  end

  def test_connection_error_wrapped
    bad = PocketBase.new("http://127.0.0.1:9")
    err = assert_raises(PocketBase::ClientResponseError) { bad.health.check }
    assert_match(/Failed to connect/, err.message)
    assert err.original_error
  end

  def test_custom_timeout_option
    result = pb.health.check(timeout: 10)
    assert_equal 200, result["code"]
  end

  def test_collection_service_caching
    assert_same pb.collection("posts"), pb.collection("posts")
    refute_same pb.collection("posts"), pb.collection("users")
  end
end
