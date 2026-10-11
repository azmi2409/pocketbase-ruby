# frozen_string_literal: true

require_relative "test_helper"

class TestCrud < PocketBaseIntegrationTest
  def test_create_and_get_one
    title = unique_title("crud")
    rec = pb.collection("posts").create("title" => title, "views" => 3)
    assert rec["id"]
    assert_equal title, rec["title"]
    assert_equal 3, rec["views"]

    fetched = pb.collection("posts").get_one(rec["id"])
    assert_equal rec["id"], fetched["id"]
    assert_equal title, fetched["title"]
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
  end

  def test_get_list_with_filter_sort_and_pagination
    t1 = unique_title("lst")
    r1 = pb.collection("posts").create("title" => t1, "views" => 10)
    r2 = pb.collection("posts").create("title" => unique_title("lst"), "views" => 20)

    list = pb.collection("posts").get_list(1, 30, filter: pb.filter("title ~ {:t}", t: "lst-"))
    assert_operator list["totalItems"], :>=, 2
    assert_equal 1, list["page"]

    sorted = pb.collection("posts").get_list(1, 30,
                                             filter: pb.filter("title ~ {:t}", t: "lst-"),
                                             sort: "-views")
    assert_equal 20, sorted["items"][0]["views"]

    page2 = pb.collection("posts").get_list(2, 1, filter: pb.filter("title ~ {:t}", t: "lst-"),
                                            sort: "-views")
    assert_equal 2, page2["page"]
    assert_equal 1, page2["items"].length
  ensure
    pb.collection("posts").delete(r1["id"]) if r1
    pb.collection("posts").delete(r2["id"]) if r2
  end

  def test_get_full_list_batches
    recs = 3.times.map do |i|
      pb.collection("posts").create("title" => unique_title("full"))
    end
    all = pb.collection("posts").get_full_list(2, filter: pb.filter("title ~ {:t}", t: "full-"))
    assert_operator all.length, :>=, 3

    all2 = pb.collection("posts").get_full_list(batch: 2, filter: pb.filter("title ~ {:t}", t: "full-"))
    assert_operator all2.length, :>=, 3
  ensure
    recs&.each { |r| pb.collection("posts").delete(r["id"]) }
  end

  def test_get_first_list_item
    title = unique_title("first")
    rec = pb.collection("posts").create("title" => title)
    found = pb.collection("posts").get_first_list_item(pb.filter("title = {:t}", t: title))
    assert_equal rec["id"], found["id"]

    err = assert_raises(PocketBase::ClientResponseError) do
      pb.collection("posts").get_first_list_item("title = 'no-such-title-xyz'")
    end
    assert_equal 404, err.status
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
  end

  def test_update
    rec = pb.collection("posts").create("title" => unique_title("upd"))
    updated = pb.collection("posts").update(rec["id"], "title" => "changed", "views" => 42)
    assert_equal "changed", updated["title"]
    assert_equal 42, updated["views"]
  ensure
    pb.collection("posts").delete(rec["id"]) if rec
  end

  def test_delete_returns_true
    rec = pb.collection("posts").create("title" => unique_title("del"))
    assert_equal true, pb.collection("posts").delete(rec["id"])
    assert_raises(PocketBase::ClientResponseError) { pb.collection("posts").get_one(rec["id"]) }
  end
end
