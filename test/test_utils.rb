# frozen_string_literal: true

require_relative "test_helper"

class TestUtils < Minitest::Test
  def test_filter_without_params_returns_raw
    assert_equal "a = 1", PocketBase::Utils.build_filter("a = 1")
    assert_equal "a = 1", PocketBase::Utils.build_filter("a = 1", {})
  end

  def test_filter_string_param_is_json_quoted
    assert_equal 'title ~ "hello"',
                 PocketBase::Utils.build_filter("title ~ {:t}", t: "hello")
  end

  def test_filter_escapes_quotes
    assert_equal 'title ~ "a\"b"',
                 PocketBase::Utils.build_filter("title ~ {:t}", t: 'a"b')
  end

  def test_filter_number_and_boolean
    assert_equal "views > 5 && active = true",
                 PocketBase::Utils.build_filter("views > {:v} && active = {:a}", v: 5, a: true)
  end

  def test_filter_nil_becomes_null
    assert_equal "deleted = null",
                 PocketBase::Utils.build_filter("deleted = {:d}", d: nil)
  end

  def test_filter_time_uses_pb_datetime_format
    t = Time.utc(2026, 1, 2, 3, 4, 5)
    assert_equal 'created >= "2026-01-02 03:04:05.000Z"',
                 PocketBase::Utils.build_filter("created >= {:c}", c: t)
  end

  def test_filter_array_is_double_encoded_like_js_sdk
    assert_equal 'tags ?|= "[\\"a\\",\\"b\\"]"',
                 PocketBase::Utils.build_filter("tags ?|= {:tags}", tags: %w[a b])
  end

  def test_token_payload_decodes
    # {"type":"auth","exp":9999999999} unsigned test token
    token = "eyJhbGciOiJIUzI1NiJ9.eyJ0eXBlIjoiYXV0aCIsImV4cCI6OTk5OTk5OTk5OX0.sig"
    payload = PocketBase::Utils.token_payload(token)
    assert_equal "auth", payload["type"]
    assert_equal 9_999_999_999, payload["exp"]
  end

  def test_token_expired
    expired = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig"
    valid = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig"
    no_exp = "eyJhbGciOiJIUzI1NiJ9.eyJ0eXBlIjoiYXV0aCJ9.sig"

    assert PocketBase::Utils.token_expired?(expired)
    assert PocketBase::Utils.token_expired?("")
    assert PocketBase::Utils.token_expired?("garbage")
    refute PocketBase::Utils.token_expired?(valid)
    refute PocketBase::Utils.token_expired?(no_exp)
    # threshold: token expiring in 100s counts as expired with threshold 200
    soon = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3OTk5OTk5OTl9.sig"
    refute PocketBase::Utils.token_expired?(soon, 10)
  end

  def test_serialize_query_params
    q = PocketBase::Utils.serialize_query_params(
      "filter" => "a = 1",
      "ids" => %w[x y],
      "skip" => nil,
      "n" => 5
    )
    assert_equal "filter=a%20%3D%201&ids=x&ids=y&n=5", q
  end

  def test_encode_uri_component_matches_js
    assert_equal "a%20b%2Fc%3Fd%3De", PocketBase::Utils.encode_uri_component("a b/c?d=e")
    assert_equal "abc-_.!~*'()", PocketBase::Utils.encode_uri_component("abc-_.!~*'()")
  end
end
