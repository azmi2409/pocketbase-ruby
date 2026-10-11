# frozen_string_literal: true

require_relative "test_helper"

class TestBatch < PocketBaseIntegrationTest
  def test_batch_create_update_delete
    batch = pb.create_batch
    batch.collection("posts").create("title" => unique_title("b1"))
    batch.collection("posts").create("title" => unique_title("b2"))

    results = batch.send
    assert_equal 2, results.length
    assert results.all? { |r| r["status"] == 200 }, results.inspect
    ids = results.map { |r| r["body"]["id"] }
    assert ids.all?

    batch2 = pb.create_batch
    batch2.collection("posts").update(ids[0], "title" => "batch-updated", "views" => 7)
    batch2.collection("posts").delete(ids[1])
    results2 = batch2.send
    assert_equal 2, results2.length
    assert results2.all? { |r| [200, 204].include?(r["status"]) }, results2.inspect

    rec = pb.collection("posts").get_one(ids[0])
    assert_equal "batch-updated", rec["title"]
    assert_equal 7, rec["views"]
    assert_raises(PocketBase::ClientResponseError) { pb.collection("posts").get_one(ids[1]) }
  ensure
    ids&.each do |id|
      begin
        pb.collection("posts").delete(id)
      rescue PocketBase::ClientResponseError
        nil
      end
    end
  end

  def test_batch_upsert
    rec = pb.collection("posts").create("title" => unique_title("upsert"))

    batch = pb.create_batch
    batch.collection("posts").upsert("id" => rec["id"], "title" => "upserted")
    batch.collection("posts").upsert("title" => unique_title("upsert-new"))
    results = batch.send

    assert_equal 2, results.length
    assert results.all? { |r| r["status"] == 200 }, results.inspect
    assert_equal "upserted", pb.collection("posts").get_one(rec["id"])["title"]
    new_id = results[1]["body"]["id"]
    assert new_id
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
    begin
      pb.collection("posts").delete(new_id)
    rescue StandardError
      nil
    end if defined?(new_id)
  end

  def test_batch_with_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "batch.png")
      File.binwrite(path, PNG_BYTES)

      batch = pb.create_batch
      batch.collection("posts").create(
        "title" => unique_title("bfile"),
        "image" => File.open(path, "rb")
      )
      results = batch.send
      assert_equal 200, results[0]["status"], results.inspect
      refute_empty results[0]["body"]["image"].to_s
      pb.collection("posts").delete(results[0]["body"]["id"])
    end
  end
end
