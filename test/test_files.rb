# frozen_string_literal: true

require_relative "test_helper"
require "net/http"

class TestFiles < PocketBaseIntegrationTest
  def test_file_upload_and_url
    rec = nil
    Dir.mktmpdir do |dir|
      path = File.join(dir, "avatar.png")
      File.binwrite(path, PNG_BYTES)

      rec = pb.collection("posts").create(
        "title" => unique_title("file"),
        "image" => File.open(path, "rb")
      )
      filename = rec["image"]
      refute_empty filename

      url = pb.files.get_url(rec, filename)
      assert_match(%r{\Ahttp://127\.0\.0\.1:8090/api/files/.+/#{rec["id"]}/}, url)

      # the file is publicly downloadable (posts viewRule is "")
      uri = URI.parse(url)
      res = Net::HTTP.get_response(uri)
      assert_equal "200", res.code
      assert_equal PNG_BYTES, res.body.b

      # thumb variant
      thumb_url = pb.files.get_url(rec, filename, thumb: "100x100")
      assert_match(/thumb=100x100/, thumb_url)

      token = pb.files.get_token
      refute_empty token

      protected_url = pb.files.get_url(rec, filename, token: token)
      assert_match(/token=/, protected_url)
    end
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
  end

  def test_get_url_with_missing_data_returns_empty
    assert_equal "", pb.files.get_url({}, "a.png")
    assert_equal "", pb.files.get_url({ "id" => "x" }, "a.png")
    assert_equal "", pb.files.get_url({ "id" => "x", "collectionId" => "y" }, "")
  end

  def test_upload_with_hash_file_value
    rec = nil
    rec = pb.collection("posts").create(
      "title" => unique_title("filehash"),
      "image" => { filename: "inline.png", content_type: "image/png", data: PNG_BYTES }
    )
    refute_empty rec["image"]
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
  end
end
